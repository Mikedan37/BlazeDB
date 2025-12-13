# Contributing to BlazeDB

Thank you for your interest in contributing to BlazeDB! This document provides guidelines and instructions for contributing.

## Code of Conduct

BlazeDB follows a professional, respectful development environment. We expect all contributors to:

- Be respectful and constructive in discussions
- Focus on technical merit and evidence
- Welcome newcomers and help them learn
- Accept constructive criticism gracefully

## Getting Started

### Prerequisites

- Swift 5.9 or later
- Xcode 15+ (for macOS/iOS development)
- Linux toolchain (for Linux development)

### Setting Up the Development Environment

1. Clone the repository:
   ```bash
   git clone https://github.com/Mikedan37/BlazeDB.git
   cd BlazeDB
   ```

2. Build the project:
   ```bash
   swift build
   ```

3. Run tests:
   ```bash
   swift test
   ```

4. Open in Xcode (optional):
   ```bash
   open BlazeDB.xcodeproj
   ```

## Development Workflow

### Branch Strategy

- `main`: Stable, production-ready code
- `develop`: Integration branch for features
- `feature/*`: Feature branches
- `fix/*`: Bug fix branches

### Making Changes

1. Create a feature branch from `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. Make your changes following the coding standards below

3. Write or update tests for your changes

4. Ensure all tests pass:
   ```bash
   swift test
   ```

5. Update documentation if needed

6. Commit your changes with clear, descriptive messages

7. Push and create a pull request

### Commit Messages

Follow conventional commit format:

```
type(scope): subject

body (optional)

footer (optional)
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `security`

Examples:
- `feat(query): add support for window functions`
- `fix(encryption): correct nonce generation for page encryption`
- `docs(readme): update installation instructions`

## Coding Standards

### Swift Style

- Follow Swift API Design Guidelines
- Use meaningful names for variables, functions, and types
- Prefer `let` over `var` when possible
- Use `guard` for early returns
- Document public APIs with doc comments

### Code Organization

- Keep files focused on a single responsibility
- Group related functionality in extensions
- Use `MARK:` comments to organize code sections
- Place public APIs in `Exports/` directory

### Security

- Never commit passwords, keys, or sensitive data
- Use secure defaults (encryption enabled by default)
- Document security implications of changes
- Review cryptographic code carefully

### Performance

- Profile before optimizing
- Document performance characteristics
- Consider memory usage and allocation patterns
- Maintain performance invariants

## Testing

### Test Requirements

- All new features must include tests
- Bug fixes must include regression tests
- Tests should be fast, isolated, and deterministic
- Use descriptive test names that explain what is being tested

### Test Organization

- Unit tests in `BlazeDBTests/`
- Integration tests in `BlazeDBIntegrationTests/`
- Performance tests in `BlazeDBTests/Performance/`
- Security tests in `BlazeDBTests/Security/`

### Running Tests

```bash
# Run all tests
swift test

# Run specific test suite
swift test --filter BlazeDBTests.QueryTests

# Run with verbose output
swift test --verbose
```

## Documentation

### Code Documentation

- Document all public APIs with doc comments
- Include parameter descriptions and return values
- Provide usage examples for complex APIs
- Document error conditions and edge cases

### README Updates

- Update README.md for user-facing changes
- Add examples for new features
- Update installation instructions if needed

### Architecture Documentation

- Document architectural decisions in `Docs/Architecture/`
- Update diagrams when architecture changes
- Explain design tradeoffs and constraints

## Pull Request Process

### Before Submitting

1. Ensure all tests pass
2. Update documentation
3. Check for code style issues
4. Review your own changes

### PR Description

Include:
- Summary of changes
- Motivation and context
- Testing performed
- Breaking changes (if any)
- Related issues

### Review Process

- All PRs require at least one approval
- Address review comments promptly
- Keep PRs focused and reasonably sized
- Respond to feedback constructively

## Areas for Contribution

### High Priority

- Performance optimizations
- Security improvements
- Test coverage expansion
- Documentation improvements
- Bug fixes

### Feature Areas

- Query optimizer improvements
- Additional index types
- Enhanced sync capabilities
- Platform-specific optimizations
- Developer tooling

### Documentation

- API reference improvements
- Tutorials and guides
- Architecture documentation
- Example projects

## Reporting Issues

### Bug Reports

Include:
- Clear description of the issue
- Steps to reproduce
- Expected vs actual behavior
- Environment details (OS, Swift version, etc.)
- Relevant code or error messages

### Feature Requests

Include:
- Use case and motivation
- Proposed solution (if any)
- Alternatives considered
- Impact on existing code

## Security Issues

For security vulnerabilities, please email security@blazedb.dev (or use GitHub Security Advisories) rather than opening a public issue.

## Questions?

- Open a discussion on GitHub
- Check existing documentation in `Docs/`
- Review existing issues and PRs

Thank you for contributing to BlazeDB!

