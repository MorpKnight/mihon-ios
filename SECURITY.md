# Security Policy

## 🔒 Our Commitment

We take the security of Mihon iOS and our users' data seriously. We are committed to protecting user privacy and ensuring the integrity of our codebase. This policy outlines how we handle security vulnerabilities and the steps we take to keep the project secure.

## 🛡️ Security Practices

### Data Protection

- **Local-First Architecture**: All user data (library, reading progress, settings) is stored locally on the device using iOS's secure data storage mechanisms
- **No Telemetry**: Mihon iOS does not collect, transmit, or share any user data without explicit consent
- **Secure Storage**: Sensitive data is stored in the Keychain where appropriate
- **Network Security**: All network communications use HTTPS with proper certificate validation

### Code Security

- **Dependency Management**: We use Swift Package Manager with version pinning to avoid supply chain attacks
- **Regular Updates**: Dependencies are regularly updated to patch security vulnerabilities
- **Code Review**: All code changes undergo peer review before merging
- **Static Analysis**: We use Xcode's built-in security scanning and recommend additional tools
- **Secrets Management**: No secrets or credentials are committed to the repository

### Extension System Security

- **Sandboxed Execution**: Extensions run in a restricted environment with limited permissions
- **Input Validation**: All extension data is validated before processing
- **Network Isolation**: Extension network requests are monitored for malicious behavior
- **User Consent**: Users must explicitly enable each extension

## 🐛 Reporting a Vulnerability

We encourage responsible disclosure of security vulnerabilities. Please follow these guidelines:

### How to Report

**DO NOT** create a public GitHub issue for security vulnerabilities.

Instead, report them privately via:

1. **GitHub Private Security Advisory**
   - Go to [Security Advisories](https://github.com/keiyoushi/mihon-ios/security/advisories)
   - Click "New draft security advisory"
   - This creates a private, encrypted report visible only to maintainers

2. **Email** (for highly sensitive issues)
   - Send details to: **security@keiyoushi.github.io**
   - Use encrypted email if possible (PGP key available upon request)
   - Include:
     - Description of the vulnerability
     - Steps to reproduce
     - Potential impact
     - Suggested fix (if any)

### What to Include

When reporting a vulnerability, please provide:

- **Vulnerability Type**: e.g., data leak, code injection, authentication bypass
- **Affected Component**: Which part of the app is vulnerable
- **Reproduction Steps**: Clear, detailed steps to reproduce the issue
- **Impact Assessment**: What could an attacker do? What data is at risk?
- **Proof of Concept**: Code or screenshots demonstrating the issue (if safe)
- **Suggested Fix**: Ideas for addressing the vulnerability (optional but helpful)

### Response Timeline

We aim to respond to security reports promptly:

- **Initial Response**: Within 48 hours acknowledging receipt
- **Status Update**: Within 7 days with assessment and plan
- **Fix Development**: Timeline depends on severity:
  - Critical: 1-7 days
  - High: 1-2 weeks
  - Medium: 2-4 weeks
  - Low: Next release cycle

### Disclosure Process

We follow responsible disclosure:

1. **Private Report**: Vulnerability reported privately
2. **Investigation**: Team verifies and assesses the issue
3. **Fix Development**: Patch is developed and tested
4. **Coordinated Disclosure**: Fix is released before public disclosure
5. **Public Announcement**: Security advisory published after patch is available
6. **CVE Assignment**: We may request CVE identifiers for significant vulnerabilities

We request that reporters **do not disclose** the vulnerability publicly until a fix is available and we've coordinated disclosure.

## 🔍 Security Audit

We periodically review our codebase for security issues:

- **Dependency Auditing**: Regular checks for vulnerable dependencies using `swift package show-dependencies` and security databases
- **Code Review**: Security-focused reviews for sensitive changes
- **Penetration Testing**: Occasional security assessments by qualified professionals
- **Static Analysis**: Use of Xcode's Security Build Settings and third-party tools

### Known Security Considerations

- **Extension Trust**: Users should only install extensions from trusted sources. Extensions have access to network and parsing capabilities.
- **Network Traffic**: While we use HTTPS, users on compromised networks could face MITM attacks. Consider using a VPN on public WiFi.
- **Jailbroken Devices**: Mihon iOS is not designed or tested for jailbroken devices, which may have reduced security.
- **Backup Security**: Backups (iCloud/iTunes) may contain reading history and preferences. Use encrypted backups.

## 📦 Dependency Security

We monitor our dependencies for vulnerabilities:

### Current Dependencies

- **SwiftUI**: Apple's framework (bundled with iOS)
- **Combine**: Apple's framework (bundled with iOS)
- **Swift Package Manager**: Apple's tooling

### Checking for Vulnerabilities

```bash
# Show all dependencies
xcodebuild -resolvePackageDependencies -showPackageGraph

# Check for known vulnerabilities (manual)
# Review GitHub security advisories for each dependency
```

If you discover a vulnerable dependency, please report it as a security issue.

## 🔐 Secure Development Guidelines

For contributors, follow these security best practices:

### Never Commit

- API keys, tokens, or credentials
- User data or personal information
- Private keys or certificates
- Hardcoded URLs with credentials
- Debug logs containing sensitive data

### Code Review Checklist

When reviewing code, check for:

- Input validation and sanitization
- Proper error handling (no information leakage)
- Secure storage of sensitive data
- Network security (HTTPS, certificate pinning if needed)
- Authentication and authorization checks
- Injection vulnerabilities (XSS, SQL, etc.)
- Secure random generation for tokens/IDs

### Testing

- Test edge cases and invalid inputs
- Test with malformed data from extensions
- Verify network error handling
- Test on different iOS versions

## 🏛️ Compliance

### App Store Guidelines

Mihon iOS complies with Apple's App Store Review Guidelines, including:
- Data collection transparency (we collect none)
- Proper use of APIs
- No hidden or undocumented functionality

### Privacy

- We do not track users
- No analytics or crash reporting (except optional Xcode metrics)
- All data remains on device
- Users control their data (export/delete)

### Copyright and Legal

- We respect copyright law
- The app does not host or distribute copyrighted content
- Extensions link to third-party sources; users are responsible for complying with those sites' terms
- DMCA takedown requests for our own content (not extensions) should be sent to security@keiyoushi.github.io

## 📞 Contact

For security issues: **security@keiyoushi.github.io**

For general questions: Use [GitHub Discussions](https://github.com/keiyoushi/mihon-ios/discussions) or [Discord](https://discord.gg/3FbCpdKbdY)

**PGP Key**: Available upon request for encrypted communication.

## 📝 Policy Updates

This security policy may be updated periodically. Significant changes will be announced via:
- GitHub Security Advisories
- Discord announcements
- Repository README updates

Last updated: March 19, 2026

## Reporting a Vulnerability

Please do not open a public issue for security-sensitive problems.

Instead, report the issue privately to the project maintainers with:

- a short description of the problem
- affected area or file
- reproduction steps if available
- expected impact

## Scope

Security reports are especially helpful for:

- authentication or lock-screen bypass
- local data exposure
- unsafe file import behavior
- web/source runtime request handling issues
- dependency-related vulnerabilities
