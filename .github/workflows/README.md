# GitHub Actions Workflows

This directory contains GitHub Actions workflow files for CI/CD.

## Workflows

### `ci.yml` - Main CI/CD Pipeline
Runs on:
- Push to `main` or `develop` branches
- Pull requests to `main` or `develop`
- Scheduled (nightly at 2 AM UTC)

Jobs:
- **test** - Build & run unit tests
- **benchmarks** - Performance benchmarks
- **chaos** - Chaos engineering tests
- **advanced** - Property-based & fuzzing tests
- **quality** - Code quality checks
- **stress** - Stress tests (CI/CD only)
- **integration** - Integration tests
- **notify** - Final status notification

### `release.yml` - Release Pipeline
Runs on:
- Push of tags matching `v*` (e.g., `v1.0.0`)

## Setup Instructions

1. **Ensure workflows are committed:**
   ```bash
   git add .github/workflows/*.yml
   git commit -m "Add GitHub Actions workflows"
   git push origin main
   ```

2. **Enable GitHub Actions:**
   - Go to your repository on GitHub
   - Click **Settings** → **Actions** → **General**
   - Under "Workflow permissions", select "Read and write permissions"
   - Click **Save**

3. **Verify workflow runs:**
   - Go to the **Actions** tab in your repository
   - You should see workflows running after pushing

## Troubleshooting

If workflows don't appear:
- Check that `.github/workflows/` directory exists
- Verify YAML syntax is correct (no tabs, proper indentation)
- Ensure you're pushing to `main` or `develop` branch
- Check repository Settings → Actions to ensure Actions are enabled

