# guvna drift scan action

The official GitHub Action for [guvna](https://guvnacloud.com): find
resources that changed outside Terraform in every root module and workspace,
fail the job on drift that matters, and get a Markdown report in the job
summary.

- **Read-only.** guvna only runs `terraform plan -refresh-only -lock=false`
  and `terraform show -json`. It never applies, imports or touches state.
- **Local-first.** The scan runs on your runner. Nothing is sent to Guvna:
  no scan results, plans, state, cloud data or telemetry.
- **Names, never values.** Reports contain resource addresses and attribute
  names only. Attribute values can hold secrets, so they are never printed,
  logged or written.
- **Verified install.** The action downloads guvna from
  [GuvnaCloud/releases](https://github.com/GuvnaCloud/releases), checks the
  Sigstore signature against guvna's own release workflow and checks the
  SHA-256 before anything runs.

## Usage

```yaml
name: Drift

on:
  schedule:
    - cron: "0 7 * * 1-5" # weekdays at 07:00 UTC
  workflow_dispatch:

permissions:
  contents: read
  id-token: write # for OIDC cloud credentials; remove if you don't use OIDC

jobs:
  drift:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
        with:
          persist-credentials: false

      - uses: hashicorp/setup-terraform@dfe3c3f87815947d99a8997f908cb6525fc44e9e # v4.0.1
        with:
          terraform_wrapper: false

      # Read-only cloud credentials, for example AWS with OIDC:
      # - uses: aws-actions/configure-aws-credentials@<full commit SHA>
      #   with:
      #     role-to-assume: ${{ secrets.GUVNA_AWS_ROLE_ARN }}
      #     aws-region: eu-west-2

      - uses: GuvnaCloud/guvna-action@<full commit SHA> # v0.1.0
        with:
          fail-on: high
```

Pin this action, like every action, to a **full commit SHA**, with the
version in a comment. Dependabot keeps the pin up to date.

`guvna drift init` in the CLI writes a complete, commented workflow like this
for you.

## Inputs

| Input | Default | Description |
|---|---|---|
| `version` | pinned per action release | guvna version to install, for example `0.1.0-beta.2` |
| `targets` | from `.guvna.yaml` or discovery | directories to scan, one per line |
| `working-directory` | `.` | where to run the scan |
| `config` | `.guvna.yaml` | path to the config file |
| `fail-on` | config, else `info` | fail the step on drift at or above `info`, `low`, `medium`, `high` or `critical`; `none` never fails |
| `init` | `auto` | when to run `terraform init`: `auto`, `always`, `never` |
| `concurrency` | `4` | targets scanned in parallel (1 to 64) |
| `timeout` | `30m` | maximum time per target |
| `job-summary` | `true` | write the Markdown report to the job summary |
| `verify-signature` | `true` | verify the Sigstore signature (the checksum is always verified) |
| `allow-pull-request-target` | `false` | see [Security](#security) |

## Outputs

| Output | Description |
|---|---|
| `exit-code` | `0` no drift at or above `fail-on`, `1` error, `2` drift found |
| `drift-found` | `true` when at least one finding was reported |
| `findings` | number of findings |
| `report-json` | path to the JSON report ([`findings.v1.json`](https://guvnacloud.com/schemas/findings.v1.json)) |
| `report-markdown` | path to the Markdown report |

Upload the reports as an artifact, or post the Markdown report on a pull
request. It is escaped for safe rendering and starts with the marker
`<!-- guvna:report -->`, so a bot can update its previous comment.

## Security

A Terraform plan **runs code**: providers and data sources from the
configuration, with whatever credentials the job has. Treat a drift scan
like a plan:

- **Never scan untrusted code with real credentials.** Don't run this action
  with secrets on `pull_request` from forks. The action refuses to run on
  `pull_request_target`, which gives untrusted code your secrets, unless you
  set `allow-pull-request-target: true` and only check out trusted code.
- **Use read-only credentials,** ideally short-lived OIDC. guvna never needs
  write access, and it takes no state lock.
- **Review `.guvna.yaml` changes like code.** Ignore rules hide drift; every
  rule needs a reason and can expire. Add the file to your CODEOWNERS.
- **Pin by SHA** and keep `verify-signature` on.

How the action itself is built:

- A composite action with no bundled dependencies. The only third-party
  action it uses is `sigstore/cosign-installer`, pinned to a full commit SHA.
- Inputs are validated and passed to the scripts as environment variables,
  never expanded inside a shell command, so they cannot inject commands.
  Targets are passed after `--`, so they can never become flags.
- It uses no `GITHUB_TOKEN` and makes no network requests other than the
  release download and the cosign signature check.

Report vulnerabilities privately: see [SECURITY.md](SECURITY.md).

## Privacy

The action sends nothing to Guvna. See the
[privacy notice](https://guvnacloud.com/privacy).

## Licence

See [LICENSE](LICENSE). guvna itself is licensed under the end-user licence
agreement included with each release.
