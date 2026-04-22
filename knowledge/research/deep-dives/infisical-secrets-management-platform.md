# Infisical — Open-Source Secrets Management Platform

**Source**: https://github.com/Infisical/infisical
**Ingested**: 2026-04-21
**Categories**: architecture, operations, tooling, research
**Confidence**: external

## Summary

Infisical is an open-source secrets management platform (99%+ TypeScript monorepo, 21k+ commits) that centralizes application secrets, API keys, database credentials, and internal PKI infrastructure. It provides a web dashboard, CLI, multiple SDKs (Node, Python, Go, Ruby, Java, .NET), and a Kubernetes operator for secret injection into workloads.

The platform uses a multilayered encryption architecture built on AES-256-GCM with 96-bit nonces, organized in a key hierarchy: Root Encryption Key → Internal KMS Root Key → Organization/Project Data Keys → Encrypted Data. It supports external KMS delegation (AWS KMS, AWS CloudHSM, GCP KMS) and HSM-sourced root keys (Thales Luna, AWS CloudHSM). The system is FIPS 140-3 compliant and has been penetration-tested by Cure53 using OWASP/ASVS/WSTG standards.

The monorepo contains backend (Node.js/TypeScript API), frontend (React dashboard), CLI, Helm charts, Kubernetes operator, and infrastructure-as-code (CloudFormation, Docker Compose). It follows an open-core model with enterprise features in an `/ee` directory. Authentication supports username/password, SAML, SSO, LDAP, AWS/GCP/Azure/OIDC/Kubernetes auth, with JWT tokens in browser memory and refresh tokens in HttpOnly cookies.

## Key Takeaways

- **Encryption architecture**: AES-256-GCM with hierarchical key wrapping (root → internal KMS root → org/project data keys). Each layer requires both server config and DB access to decrypt — defense in depth. Keys generated via Node.js crypto CSPRNG.
- **External KMS integration**: Organizations can delegate project data key encryption to AWS KMS, CloudHSM, or GCP KMS, retaining their own key policies and audit logs.
- **Auth diversity**: 10+ machine identity auth methods (Kubernetes, AWS, GCP, Azure, OIDC, JWT, LDAP, OCI, Alibaba Cloud, Universal Auth) with custom TTLs, IP restrictions, and usage caps.
- **RBAC + ABAC**: Role-based and attribute-based access control at organization and project levels, with additional privilege constraints and group membership inheritance.
- **Threat model boundaries**: Explicitly out of scope — uncontrolled storage backend access, runtime memory intrusion, compromised client credentials, admin config tampering, physical access, social engineering. In scope — eavesdropping, data tampering, unauthorized access, unaccountable actions, storage breaches, anomalies, system vulns.
- **Zero-knowledge option**: Secret values can be physically inaccessible to Infisical employees (opt-in to bypass for support scenarios).
- **Secret syncing pattern**: Acts as source-of-truth pushing to GitHub, Vercel, AWS, Terraform, Ansible — integrates into existing workflows rather than forcing migration.
- **Dynamic secrets and rotation**: On-demand credential generation for PostgreSQL, MySQL, RabbitMQ with automated rotation.
- **PKI capabilities**: Internal CA hierarchy, external CA integration (Let's Encrypt, DigiCert, MS AD CS), ACME/EST enrollment, certificate syncs to AWS ACM and Azure Key Vault.
- **Infrastructure (cloud)**: Multi-AZ AWS RDS with auto-failover, multi-AZ ElastiCache Redis, multi-AZ ECS; disaster recovery via AWS Global Datastore and cross-region RDS replicas. All traffic through Cloudflare with TLS 1.2 minimum.

## Relevance to Project

Infisical's architecture is relevant to root-archetype in several ways:

1. **Secrets management for audit pipelines**: If the Plamen security audit pipeline ever needs to manage API keys (RPC URLs, MCP tool credentials, external service tokens), Infisical's self-hosted mode offers a structured alternative to `.env` files.
2. **Key hierarchy pattern**: The root → KMS root → data key hierarchy is a well-tested pattern for any system that encrypts sensitive artifacts (e.g., audit scratchpads containing client source code or findings).
3. **Auth method diversity as research input**: The 10+ machine identity auth methods represent a comprehensive catalog of cloud-native auth patterns — useful reference when auditing protocols that integrate with cloud infrastructure.
4. **Monorepo architecture reference**: TypeScript monorepo with backend/frontend/CLI/operator/infra-as-code in one repo mirrors the multi-component structure root-archetype manages. Their `/ee` open-core pattern is a well-executed example.
5. **Threat model as template**: Their explicit in-scope/out-of-scope threat model is a good reference for documenting trust assumptions in audit reports.
