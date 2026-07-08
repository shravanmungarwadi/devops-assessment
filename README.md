# DevOps Assessment: Terraform + Database Reliability

Hotel booking platform infrastructure design (Terraform, plan-only) plus a
fully runnable local database exercise (Docker Compose, Postgres, backup /
restore, query optimization).

## Repo structure

```
infra/
  modules/
    network/     # VPC, subnets, routing, NAT, security groups
    rds/         # RDS instance (Postgres/MySQL)
    ecs/         # ALB, ECS cluster, task definition, service, IAM
  envs/
    dev/         # small/cheap, short retention, deletion protection off
    prod/        # bigger, long retention, deletion protection on, multi-AZ
.github/workflows/terraform.yml   # fmt/init/validate/plan on every PR
sql/
  migrations/    # 001_create_tables.sql, 002_add_indexes.sql
  seed/          # seed.sql (150 bookings, 5 cities, 4 orgs, events)
scripts/
  backup.sh
  restore.sh
docker-compose.yml
.env.example
```

---

## Part 1 & 2 - Terraform infrastructure

**Traffic flow:** `Internet -> ALB (public subnets) -> ECS/Fargate (private subnets) -> RDS (private subnets)`

- `modules/network` - VPC with 2 public + 2 private subnets across 2 AZs, an
  Internet Gateway for the public side, a single NAT Gateway so private-subnet
  ECS tasks can still reach the internet/AWS APIs, and three security groups:
  - **ALB SG** - only one that accepts traffic from `0.0.0.0/0` (ports 80/443).
  - **ECS SG** - only accepts traffic from the **ALB SG**, on the container port.
  - **RDS SG** - only accepts traffic from the **ECS SG**, on the DB port.
- `modules/rds` - a single `aws_db_instance`, placed in private subnets only,
  `publicly_accessible = false`. Even if a security group rule were ever
  misconfigured, RDS still has no route from the internet because it isn't in
  a public subnet - this is defense in depth, not just the SG rule.
- `modules/ecs` - ALB + target group + listener, an ECS cluster, a Fargate
  task definition (execution role + task role kept separate, least-privilege),
  and a service that places tasks in the private subnets with
  `assign_public_ip = false`.

**Environments** (`infra/envs/dev`, `infra/envs/prod`) call the same three
modules with different `.tfvars`:

| Setting                  | dev                | prod                |
|---------------------------|--------------------|----------------------|
| RDS instance class        | `db.t4g.micro`     | `db.r6g.large`       |
| Backup retention          | 1 day              | 30 days              |
| Deletion protection       | `false`            | `true`               |
| Multi-AZ standby          | `false`            | `true`               |
| Final snapshot on destroy | skipped            | taken                |
| ECS task size / count     | 256 CPU / 1 task   | 1024 CPU / 2 tasks   |
| Terraform state key       | `.../dev/...`      | `.../prod/...`       |

Each environment also has its own S3 backend key (`versions.tf`), so dev and
prod state can never collide.

### Running it (plan-only, no AWS deployment needed)

```bash
cd infra/envs/dev     # or infra/envs/prod

terraform fmt -check -recursive ../../..
terraform init -backend=false          # no AWS backend/creds needed for review
terraform validate

terraform plan -refresh=false \
  -var-file="dev.tfvars" \
  -var="db_password=any-placeholder-value"
```

`db_password` has no default in `prod` on purpose (real secrets should never
have a default or live in `.tfvars`) - pass it via `-var` or `TF_VAR_db_password`.

I don't have Terraform installed in the environment I used to build this, so
I validated the HCL a different way: every `.tf` file was parsed with a HCL2
parser, and I cross-checked that every module input/output referenced in
`envs/dev` and `envs/prod` is actually declared in the corresponding module
(no typo'd variable or output names, all required variables supplied). You
should still run the commands above yourself, or let the GitHub Actions
workflow below do it on your first PR.

---

## Part 3 - Terraform CI (implemented, not skipped)

`.github/workflows/terraform.yml` runs on every PR that touches `infra/**`,
for **both** `dev` and `prod` as a matrix:

1. `terraform fmt -check -recursive`
2. `terraform init -backend=false` (no AWS credentials needed in CI)
3. `terraform validate`
4. `terraform plan -refresh=false` (with a placeholder `db_password`)

The plan is surfaced two ways:
- **PR comment** - posted automatically via `actions/github-script`, one
  comment per environment, wrapped in a collapsible `<details>` block.
- **Workflow artifact** - the full plan text is uploaded as
  `terraform-plan-dev` / `terraform-plan-prod`, for plans too long for a
  readable comment.

---

## Part 4, 5, 6 - Local database (Postgres via Docker Compose)

### Setup

```bash
cp .env.example .env
docker compose up -d
```

On first startup (empty data volume), the official `postgres:16` image
automatically runs, in order, everything mounted into
`/docker-entrypoint-initdb.d/`:

1. `sql/migrations/001_create_tables.sql` - creates `hotel_bookings` and
   `booking_events`.
2. `sql/migrations/002_add_indexes.sql` - adds the reporting index.
3. `sql/seed/seed.sql` - inserts 150 bookings + ~88 booking events.

No extra command is needed - `docker compose up` alone gets you schema +
data. To re-seed later without recreating the container, run:

```bash
docker compose exec -T db psql -U app_admin -d hotelbook < sql/seed/seed.sql
```

(`seed.sql` starts with a `TRUNCATE ... RESTART IDENTITY CASCADE`, so it's
safe to re-run.)

### Schema

`hotel_bookings` matches the suggested schema, plus two check constraints
(`checkout_date > checkin_date`, `amount >= 0`) and `pgcrypto` for
`gen_random_uuid()` defaults. `booking_events` has a foreign key to
`hotel_bookings(id)` with `ON DELETE CASCADE`, and its own index on
`booking_id` (Postgres does not index foreign key columns automatically).

### Seed data

`sql/seed/seed.sql` is pure SQL (`generate_series`, no external scripting
language needed) and produces:
- 150 hotel bookings across **4 orgs** and **5 cities**
  (delhi, mumbai, bengaluru, pune, hyderabad) and **4 statuses**
  (confirmed, cancelled, pending, completed).
- `created_at` spread over the last ~60 days, so filtering "last 30 days"
  returns a meaningful (not all-or-nothing) subset - verified below.
- ~88 booking events attached to ~60% of bookings.

### Query optimization

Target query:

```sql
SELECT org_id, status, COUNT(*), SUM(amount)
FROM hotel_bookings
WHERE city = 'delhi'
  AND created_at >= NOW() - INTERVAL '30 days'
GROUP BY org_id, status;
```

**Index added:** `idx_hotel_bookings_city_created_at` - a composite B-tree on
`(city, created_at)`.

**Why this shape, in this order:**
- `city` is an **equality** filter, so it goes first - Postgres can jump
  straight to the `'delhi'` rows in the index.
- `created_at` is a **range** filter (`>=`), so it goes second - within the
  `'delhi'` rows, Postgres can also use the index to narrow to the last 30
  days, instead of scanning all of delhi's history.
- `org_id` / `status` are `GROUP BY` columns, not filter columns - they don't
  need to be in the index; aggregating them is cheap once the row set is
  already small.

**Verified with `EXPLAIN ANALYZE`** (actual output, captured while building
this, on the 150-row seed set):

*Before the index (Seq Scan):*
```
GroupAggregate (actual time=0.064..0.069 rows=4 loops=1)
  ->  Sort (actual time=0.054..0.055 rows=17 loops=1)
        ->  Seq Scan on hotel_bookings (actual time=0.007..0.027 rows=17 loops=1)
              Filter: (city = 'delhi' AND created_at >= now() - '30 days')
              Rows Removed by Filter: 133
```

*After the index (Index Scan):*
```
GroupAggregate (actual time=0.063..0.068 rows=4 loops=1)
  ->  Sort (actual time=0.053..0.054 rows=17 loops=1)
        ->  Index Scan using idx_hotel_bookings_city_created_at on hotel_bookings
              (actual time=0.020..0.026 rows=17 loops=1)
              Index Cond: (city = 'delhi' AND created_at >= now() - '30 days')
```

**Honest note on scale:** at only 150 rows, the *absolute* timing difference
is negligible (both sub-millisecond) - Postgres' planner can even choose to
go back to a Seq Scan on a table this tiny, because for a handful of pages a
sequential scan genuinely has less overhead than an index scan. What matters
is the **plan shape change** (`Seq Scan` -> `Index Scan`, with
`Rows Removed by Filter: 133` disappearing): as the table grows into the
tens/hundreds of thousands of rows - which is the point of adding an index in
the first place - the sequential scan's cost grows linearly with table size
while the index scan's cost stays roughly flat. I confirmed the index is
correctly chosen at that point by forcing `SET enable_seqscan = off` and
seeing Postgres pick a `Bitmap Index Scan` using this exact index.

A commented-out covering-index variant
(`INCLUDE (org_id, status, amount)`) is left in
`002_add_indexes.sql` for reference - it would let Postgres answer the whole
query from the index alone (an Index-Only Scan), at the cost of a larger
index and slightly slower writes.

### Backup and restore

```bash
./scripts/backup.sh
```
- Requires the compose stack to be running (`docker compose up -d`).
- Runs `pg_dump` **inside** the `db` container (no local Postgres client
  needed on your machine).
- Writes a timestamped, self-contained dump (`--clean --if-exists`) to
  `backups/backup_hotelbook_<UTC timestamp>.sql`, and updates a
  `backups/latest.sql` symlink to point at it.

```bash
./scripts/restore.sh                      # restores backups/latest.sql
./scripts/restore.sh backups/backup_xyz.sql   # or a specific file
```
- Restores into a **new** database, `hotelbook_restore_check` - the original
  `hotelbook` database is never touched. This is the "fresh local database"
  the task description asks for.
- Drops `hotelbook_restore_check` if it already exists (so the script is
  safe to re-run), creates it fresh, and loads the backup into it.

**How the script verifies restore worked:** it runs
`SELECT COUNT(*) FROM <table>` against both the original and restored
databases for `hotel_bookings` and `booking_events`, prints them side by
side, and exits non-zero if any table's counts don't match. I ran this
end-to-end while building the repo: 150/150 `hotel_bookings` and 88/88
`booking_events` matched exactly, and the index (`idx_hotel_bookings_city_created_at`)
was present in the restored database too.

You can also inspect the restored database by hand:
```bash
docker compose exec db psql -U app_admin -d hotelbook_restore_check
```
and drop it when done:
```bash
docker compose exec db psql -U app_admin -d postgres -c "DROP DATABASE hotelbook_restore_check;"
```

---

## Design decisions / assumptions

- **Postgres over MySQL** - the suggested schema uses `UUID`, `JSONB`, and
  `NOW() - INTERVAL`, all of which are native Postgres; MySQL would need
  workarounds (`CHAR(36)`, `JSON`, `DATE_SUB`), so Postgres was the more
  natural fit.
- **Single NAT Gateway** rather than one per AZ, to keep the example
  cost-realistic for a take-home; a note in the module says where to add a
  second one for stricter prod HA.
- **`db_password` has no default in `prod.tfvars`** on purpose - it must be
  supplied via `TF_VAR_db_password` or a secrets manager, never committed.
- **CI runs `terraform init -backend=false`** - the assessment doesn't
  require a real AWS account/S3 backend, so CI validates and plans without
  needing AWS credentials in GitHub Secrets. If you want to demo the *actual*
  documented backend, create the S3 bucket + DynamoDB table and update the
  bucket names in `versions.tf`, then remove `-backend=false` from both the
  workflow and your local `terraform init`.
- **Seed data is pure SQL** (no Python/Node dependency) so `docker compose up`
  is the only command needed to get a fully seeded database - one less moving
  part for a reviewer to install.

## What I verified locally before submitting

- Every `.tf` file parses as valid HCL; every module input/output reference
  across `envs/dev` and `envs/prod` matches an actual declared variable/output
  (no typos).
- `docker-compose.yml` and the GitHub Actions workflow both parse as valid
  YAML.
- Ran the actual migrations, seed script, `EXPLAIN ANALYZE` before/after the
  index, and a full backup -> restore -> row-count-verification cycle against
  a real Postgres 16 instance - not just written blind.
