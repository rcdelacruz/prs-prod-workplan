# Glossary

## Overview

This glossary provides definitions for technical terms, acronyms, and concepts used throughout the PRS on-premises deployment documentation.

## A

**API (Application Programming Interface)**
: A set of protocols and tools for building software applications. In PRS, the REST API allows external systems to interact with the procurement system.

**Audit Log**
: A chronological record of system activities and user actions for security and compliance purposes. PRS maintains comprehensive audit logs for all transactions.

**Authentication**
: The process of verifying the identity of a user or system. PRS supports multiple authentication methods including local accounts and external identity providers.

**Authorization**
: The process of determining what actions an authenticated user is allowed to perform. PRS implements role-based access control (RBAC).

**Automated Backup**
: Scheduled backup processes that run without manual intervention. PRS includes daily automated backups with verification.

## B

**Backend**
: The server-side component of the application that handles business logic, database operations, and API endpoints. Built with Node.js.

**Backup Retention**
: The policy defining how long backup files are kept before deletion. PRS maintains 30 days of local backups and 90 days of offsite backups.

**Business Logic**
: The core functionality and rules that define how the procurement system operates, including approval workflows and validation rules.

## C

**Cache Hit Ratio**
: The percentage of data requests served from cache rather than the database. A higher ratio indicates better performance.

**Chunk**
: In TimescaleDB, a partition of a hypertable that contains data for a specific time range. Chunks enable efficient data management and querying.

**Cold Storage**
: Storage tier for infrequently accessed data, typically on slower but higher-capacity drives (HDD in PRS deployment).

**Compression**
: The process of reducing data size to save storage space. TimescaleDB provides automatic compression for older data chunks.

**Container**
: A lightweight, portable unit that packages an application and its dependencies. PRS uses Docker containers for all services.

**CORS (Cross-Origin Resource Sharing)**
: A security mechanism that allows web applications to make requests to different domains. Configured in PRS for secure frontend-backend communication.

## D

**Data Movement**
: The automatic process of moving data between storage tiers based on age and access patterns. PRS moves data from SSD to HDD after 30 days.

**Data Retention**
: Policies defining how long different types of data are kept in the system. PRS implements a zero-deletion policy with automatic archival.

**Database Migration**
: The process of updating database schema or moving data between database versions. Includes scripts to modify table structures and data.

**Docker Compose**
: A tool for defining and running multi-container Docker applications using YAML configuration files.

**Dual Storage Architecture**
: PRS's storage strategy using both SSD (fast) and HDD (capacity) storage tiers for optimal performance and cost efficiency.

## E

**Environment Variables**
: Configuration values stored outside the application code, used to customize behavior for different deployment environments.

**ETL (Extract, Transform, Load)**
: The process of extracting data from source systems, transforming it to fit operational needs, and loading it into the target system.

## F

**Failover**
: The automatic switching to a backup system when the primary system fails. PRS includes failover capabilities for high availability.

**Frontend**
: The client-side component of the application that users interact with directly. Built with React and Vite.

**Full Backup**
: A complete backup of all data in the system. PRS performs daily full backups for comprehensive data protection.

## G

**Grafana**
: An open-source analytics and monitoring platform used in PRS for creating dashboards and visualizing system metrics.

**GPU (Graphics Processing Unit)**
: Specialized hardware for parallel processing. Not required for PRS deployment but can accelerate certain data processing tasks.

## H

**Health Check**
: Automated tests that verify system components are functioning correctly. PRS includes comprehensive health checks for all services.

**Hot Storage**
: Storage tier for frequently accessed data, typically on faster drives (SSD in PRS deployment).

**Hypertable**
: TimescaleDB's abstraction for time-series data that automatically partitions data across multiple chunks for efficient querying.

## I

**Incremental Backup**
: A backup that only includes data changed since the last backup. More efficient than full backups for frequent backup schedules.

**Index**
: A database structure that improves query performance by creating shortcuts to data. PRS uses optimized indexes for common query patterns.

**Infrastructure as Code (IaC)**
: The practice of managing infrastructure through code rather than manual processes. PRS deployment scripts follow IaC principles.

## J

**JWT (JSON Web Token)**
: A secure method for transmitting information between parties. Used in PRS for user authentication and session management.

## K

**Kubernetes**
: Container orchestration platform. While PRS uses Docker Compose, it can be adapted for Kubernetes deployment.

## L

**Load Balancer**
: A system that distributes incoming requests across multiple servers. Nginx serves as the load balancer in PRS deployment.

**Log Rotation**
: The process of archiving and managing log files to prevent disk space issues. PRS implements automatic log rotation.

## M

**Microservices**
: An architectural approach where applications are built as a collection of small, independent services. PRS uses a microservices architecture.

**Migration**
: The process of moving from one system version to another, including data and schema changes.

**Monitoring**
: The continuous observation of system performance and health. PRS includes comprehensive monitoring with Prometheus and Grafana.

## N

**Nginx**
: A web server and reverse proxy used in PRS for handling HTTP requests, SSL termination, and load balancing.

**Node.js**
: A JavaScript runtime used for building the PRS backend services.

## O

**On-Premises**
: Software deployed and run on the organization's own hardware and infrastructure, as opposed to cloud-based deployment.

**Orchestration**
: The automated coordination of multiple services or processes. Docker Compose orchestrates PRS services.

## P

**Point-in-Time Recovery (PITR)**
: The ability to restore a database to a specific moment in time. Enabled through WAL archiving in PRS.

**PostgreSQL**
: An open-source relational database system used as the foundation for TimescaleDB in PRS.

**Prometheus**
: An open-source monitoring and alerting system used in PRS for collecting and storing metrics.

**Procurement**
: The process of acquiring goods and services. PRS is a system designed to manage and automate procurement workflows.

## Q

**Query Optimization**
: The process of improving database query performance through better indexing, query structure, and execution plans.

**Queue**
: A data structure for managing tasks in order. PRS uses Redis queues for background job processing.

## R

**RAID (Redundant Array of Independent Disks)**
: A storage technology that combines multiple drives for improved performance and/or redundancy. PRS uses RAID1 for SSD and RAID5 for HDD.

**Redis**
: An in-memory data store used in PRS for caching and session management.

**Requisition**
: A formal request for goods or services within an organization. The core entity managed by PRS.

**REST API**
: A web service architecture style used by PRS for communication between frontend and backend components.

**Rollback**
: The process of reverting to a previous version of software or data after a failed update or deployment.

## S

**Scaling**
: The process of adjusting system capacity to handle changing load. Can be vertical (more powerful hardware) or horizontal (more servers).

**SSL/TLS**
: Security protocols for encrypting data transmission. PRS uses SSL/TLS for all web communications.

**SSD (Solid State Drive)**
: Fast storage technology used in PRS for hot data storage and high-performance operations.

## T

**TimescaleDB**
: A time-series database built on PostgreSQL, used in PRS for efficient storage and querying of time-based data.

**Throughput**
: The amount of work performed in a given time period. Measured in requests per second for web applications.

**Two-Factor Authentication (2FA)**
: A security method requiring two different authentication factors. Optional feature in PRS for enhanced security.

## U

**Uptime**
: The amount of time a system is operational and available. PRS is designed for high uptime with redundancy and monitoring.

**User Interface (UI)**
: The visual elements and controls that users interact with. PRS provides a modern web-based UI.

## V

**VACUUM**
: A PostgreSQL operation that reclaims storage space and updates statistics. Part of regular PRS maintenance procedures.

**Virtual Machine (VM)**
: A software emulation of a computer system. PRS can be deployed on VMs or physical hardware.

**Volume**
: In Docker, a mechanism for persisting data generated and used by containers. PRS uses volumes for database and file storage.

## W

**WAL (Write-Ahead Logging)**
: A database technique where changes are logged before being applied. Used in PRS for point-in-time recovery.

**Webhook**
: A method for applications to provide real-time information to other applications. PRS supports webhooks for external integrations.

**Workflow**
: A sequence of processes through which work passes. PRS manages procurement workflows including approvals and processing.

## X

**XML**
: A markup language for storing and transporting data. Some PRS integrations may use XML format for data exchange.

## Y

**YAML**
: A human-readable data serialization standard. Used in PRS for Docker Compose configuration files.

## Z

**Zero-Deletion Policy**
: PRS's data retention strategy where no data is permanently deleted, only archived to different storage tiers.

**Zone**
: In networking and security contexts, a logical grouping of resources with similar security requirements.

---

## Acronyms and Abbreviations

| Acronym | Full Form | Description |
|---------|-----------|-------------|
| **API** | Application Programming Interface | Interface for software communication |
| **CPU** | Central Processing Unit | Main processor of a computer |
| **CRUD** | Create, Read, Update, Delete | Basic database operations |
| **CSV** | Comma-Separated Values | File format for data exchange |
| **DNS** | Domain Name System | System for translating domain names to IP addresses |
| **GPU** | Graphics Processing Unit | Specialized processor for parallel computing |
| **HDD** | Hard Disk Drive | Traditional magnetic storage device |
| **HTTP** | Hypertext Transfer Protocol | Protocol for web communication |
| **HTTPS** | HTTP Secure | Encrypted version of HTTP |
| **I/O** | Input/Output | Data transfer operations |
| **JSON** | JavaScript Object Notation | Data interchange format |
| **JWT** | JSON Web Token | Token-based authentication standard |
| **LDAP** | Lightweight Directory Access Protocol | Directory service protocol |
| **NGINX** | Engine X | Web server and reverse proxy |
| **OS** | Operating System | System software managing hardware |
| **PDF** | Portable Document Format | File format for documents |
| **PITR** | Point-in-Time Recovery | Database recovery to specific time |
| **PRS** | Procurement and Requisition System | The application system |
| **QPS** | Queries Per Second | Database performance metric |
| **RAID** | Redundant Array of Independent Disks | Storage redundancy technology |
| **RAM** | Random Access Memory | Computer memory |
| **RBAC** | Role-Based Access Control | Access control method |
| **REST** | Representational State Transfer | Web service architecture |
| **SLA** | Service Level Agreement | Performance guarantee |
| **SQL** | Structured Query Language | Database query language |
| **SSD** | Solid State Drive | Flash-based storage device |
| **SSL** | Secure Sockets Layer | Encryption protocol |
| **TLS** | Transport Layer Security | Successor to SSL |
| **UI** | User Interface | User interaction layer |
| **UPS** | Uninterruptible Power Supply | Backup power system |
| **URL** | Uniform Resource Locator | Web address |
| **UUID** | Universally Unique Identifier | Unique identifier standard |
| **VM** | Virtual Machine | Virtualized computer system |
| **VPN** | Virtual Private Network | Secure network connection |
| **WAL** | Write-Ahead Logging | Database logging technique |
| **XML** | eXtensible Markup Language | Markup language for data |
| **YAML** | YAML Ain't Markup Language | Data serialization standard |

---

!!! tip "Quick Reference"
    Use Ctrl+F (or Cmd+F on Mac) to quickly search for specific terms in this glossary.

!!! success "Comprehensive Coverage"
    This glossary covers all major technical terms used in the PRS on-premises deployment documentation and operations.
