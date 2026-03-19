# HelixBeat – Country & Region Reference

## Active deployments

| Country | Code | AWS Region     | Dev CIDR       | Staging CIDR   | Domain (dev)              | Domain (staging)              |
|---------|------|----------------|----------------|----------------|---------------------------|-------------------------------|
| US      | `us` | us-east-1      | 10.10.0.0/16   | 10.30.0.0/16   | us.helixbeat.com          | staging-us.helixbeat.com      |
| India   | `in` | ap-south-1     | 10.20.0.0/16   | 10.40.0.0/16   | in.helixbeat.com          | staging-in.helixbeat.com      |

## Planned countries – Asia Pacific & Middle East

| Country   | Code | AWS Region       | Dev CIDR       | Staging CIDR   | Domain (dev)              |
|-----------|------|------------------|----------------|----------------|---------------------------|
| Oman      | `om` | me-central-1     | 10.50.0.0/16   | 10.51.0.0/16   | om.helixbeat.com          |
| Malaysia  | `my` | ap-southeast-5   | 10.60.0.0/16   | 10.61.0.0/16   | my.helixbeat.com          |
| Sri Lanka | `lk` | ap-south-1 †     | 10.70.0.0/16   | 10.71.0.0/16   | lk.helixbeat.com          |
| Indonesia | `id` | ap-southeast-3   | 10.80.0.0/16   | 10.81.0.0/16   | id.helixbeat.com          |

> † Sri Lanka: No dedicated AWS region. Nearest is ap-south-1 (Mumbai, ~1700 km).
>   Monitor https://aws.amazon.com/about-aws/global-infrastructure/ for future PoPs.
>   If in-country data residency is required, evaluate AWS Local Zones or Outposts.

## Planned countries – Americas, Europe, Oceania & Africa

| Country      | Code | AWS Region       | Dev CIDR       | Staging CIDR   | Domain (dev)              |
|--------------|------|------------------|----------------|----------------|---------------------------|
| Canada       | `ca` | ca-central-1     | 10.90.0.0/16   | 10.91.0.0/16   | ca.helixbeat.com          |
| UK           | `gb` | eu-west-2        | 10.100.0.0/16  | 10.101.0.0/16  | gb.helixbeat.com          |
| Australia    | `au` | ap-southeast-2   | 10.110.0.0/16  | 10.111.0.0/16  | au.helixbeat.com          |
| Africa       | `za` | af-south-1 ‡     | 10.120.0.0/16  | 10.121.0.0/16  | af.helixbeat.com          |

> ‡ Africa: The only dedicated AWS Africa region is af-south-1 (Cape Town, South Africa).
>   This serves all African operations initially. As HelixBeat expands to Nigeria, Kenya,
>   Egypt, etc., use the same `za` deployment with Route 53 geo-routing, or revisit once
>   AWS opens additional Africa PoPs (reportedly planned for Nigeria).

## Adding a new country

1. **Bootstrap remote state** (run once per country):
   ```bash
   ./scripts/bootstrap.sh dev <code> <region>
   ./scripts/bootstrap.sh staging <code> <region>
   ```

2. **Create environment directory**:
   ```bash
   cp -r terraform/environments/dev-in terraform/environments/dev-<code>
   ```
   Edit the new `main.tf`:
   - `country_code = "<code>"`
   - `aws_region   = "<region>"`
   - `vpc_cidr     = "10.XX.0.0/16"`   ← pick next unused /16 from table above
   - `availability_zones = [...]`
   - `domain_name  = "<code>.helixbeat.com"`
   - `ec2_ami_id   = "<Amazon Linux 2023 AMI in target region>"`
   - Backend bucket/table names: `helixbeat-tfstate-dev-<code>`

3. **Deploy**:
   ```bash
   cd terraform/environments/dev-<code>
   terraform init && terraform plan && terraform apply
   ```

## CIDR allocation rules

- Each country gets a pair of `/16` blocks: `10.X0.0.0/16` (dev) and `10.X1.0.0/16` (staging).
- No two environments share a CIDR — required for future Transit Gateway / VPC Peering.
- Reserve `10.0.0.0/16` – `10.9.0.0/16` for shared services (Transit Gateway, Direct Connect).
- Allocation sequence: US=10, IN=20, OM=50, MY=60, LK=70, ID=80, CA=90, GB=100, AU=110, ZA=120.
- Next available block for a new country: `10.130.0.0/16` (dev) / `10.131.0.0/16` (staging).

## AMI IDs (Amazon Linux 2023 – update quarterly)

Always run the lookup command below before deploying to a new region — AMI IDs
are region-specific and change with each AL2023 release.

| Region           | Country     | AMI ID (last verified)      | Status           |
|------------------|-------------|-----------------------------|------------------|
| us-east-1        | US          | ami-0c02fb55956c7d316       | Active           |
| ap-south-1       | India / LK  | ami-0f58b397bc5c1f2e8       | Active           |
| me-central-1     | Oman        | ami-0d7d7c0c06bce06c0       | Verify before use |
| ap-southeast-5   | Malaysia    | —                           | Verify before use |
| ap-southeast-3   | Indonesia   | —                           | Verify before use |
| ca-central-1     | Canada      | —                           | Verify before use |
| eu-west-2        | UK          | —                           | Verify before use |
| ap-southeast-2   | Australia   | —                           | Verify before use |
| af-south-1       | Africa      | —                           | Verify before use |

Run this to get the latest AL2023 AMI in any region:
```bash
AWS_PROFILE=helixbeat aws ec2 describe-images \
  --region <region> \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
  --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
  --output text
```

## Region capability matrix

The `env-base` module auto-selects settings from this table via its `region_defaults` local map.
You do not need to set these manually unless you want to override the auto-detected values.

| Country    | AWS Region       | EC2/EKS nodes | DocDB class | EFS mode | SecurityHub standards | GuardDuty advanced |
|------------|------------------|---------------|-------------|----------|-----------------------|--------------------|
| US         | us-east-1        | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| India      | ap-south-1       | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| Canada     | ca-central-1     | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| UK         | eu-west-2        | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| Australia  | ap-southeast-2   | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| Oman       | me-central-1     | **m6i.large** | **db.r5**   | elastic  | ⚠️ disabled           | ⚠️ disabled        |
| Malaysia   | ap-southeast-5   | **m6i.large** | **db.r5**   | **bursting** | ⚠️ disabled       | ⚠️ disabled        |
| Sri Lanka  | ap-south-1       | m5.large      | db.r6g      | elastic  | ✅                    | ✅                 |
| Indonesia  | ap-southeast-3   | **m6i.large** | **db.r5**   | elastic  | ⚠️ disabled           | ⚠️ disabled        |
| Africa     | af-south-1       | **m6i.large** | **db.r5**   | elastic  | ⚠️ disabled           | ⚠️ disabled        |

**Bold** = differs from the mature-region default. All differences are handled automatically by the
`region_defaults` map in `terraform/env-base/main.tf` — no manual changes needed per environment.

> SecurityHub CIS/FSBP standards disabled in newer regions = SecurityHub itself still runs,
> just without the specific benchmark subscriptions. AWS Config rules remain active as compensating control.

> GuardDuty advanced disabled = S3 data-plane monitoring still active; Kubernetes audit logs and
> EBS malware scanning skipped where not yet supported.

