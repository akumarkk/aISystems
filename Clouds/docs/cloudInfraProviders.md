

## 1. Cloud Provider Native Infrastructure Engines

| Cloud Service Provider (CSP) | Native IaC Engine / Tool | Modern Native Abstraction / Language | Native Template Format | Managed Deployment Service |
| :--- | :--- | :--- | :--- | :--- |
| **Amazon Web Services (AWS)** | **AWS CloudFormation** | **AWS CDK** *(compiles to CloudFormation)* | YAML / JSON | CloudFormation Stacks / AWS SAM |
| **Microsoft Azure** | **Azure Resource Manager (ARM)** | **Azure Bicep** *(compiles to ARM JSON)* | JSON (ARM) or Bicep Syntax | Azure Resource Manager Deployments |
| **Google Cloud Platform (GCP)** | **Google Cloud Infrastructure Manager** | **Deployment Manager** *(legacy)* | YAML / Terraform (HCL) | GCP Infrastructure Manager / Cloud Build |
| **Oracle Cloud Infrastructure (OCI)** | **OCI Resource Manager** | Terraform (HCL) | HCL (Terraform-native) | OCI Resource Manager Stacks |
| **Alibaba Cloud** | **Resource Orchestration Service (ROS)** | **ROS CDK** | JSON / YAML | ROS Deployments |
| **IBM Cloud** | **IBM Cloud Schematics** | Terraform (HCL) & Ansible | HCL / Ansible Playbooks | IBM Schematics Engine |
| **Huawei Cloud** | **Resource Template Service (RTS)** | RTS Syntax | YAML / JSON | RTS Engine |

---

## 2. Multi-Cloud & Industry Standard Alternatives

* **Terraform (by HashiCorp):** The industry standard declarative tool using HashiCorp Configuration Language (HCL).
* **OpenTofu:** An open-source, community-driven fork of Terraform.
* **Pulumi:** Provides imperative infrastructure management using real programming languages (TypeScript, Python, Go, C#).

---

## 3. Naming Conventions & Terminology

### Industry Terms for Cloud Providers
* **Cloud Service Provider (CSP):** Standard technical/formal term (AWS, Azure, GCP).
* **Hyperscalers:** Enterprise/executive term for top-tier global providers (AWS, Azure, GCP).
* **Cloud Infrastructure Provider:** Specific to core compute, network, and storage vendors.

### Naming Guide (Repos, Directories, Pipelines)
* **`infra` / `infrastructure`:** Best for technical deliverables, repositories (`payment-service-infra`), IaC directories (`/infra`), and Terraform modules.
* **`cloud`:** Best for high-level organizational scope (e.g., `cloud-platform` team, AWS Landing Zone accounts).
* **`digital-cloud`:** Avoid in technical contexts; primarily a marketing/executive term.

---

## 4. Managed NoSQL Deployment Examples (Equivalent to AWS DynamoDB)

### A. Azure Bicep (Cosmos DB)
```bicep
// main.bicep
param accountName string = 'cosmos-db-${uniqueString(resourceGroup().id)}'
param location string = resourceGroup().location

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2023-04-15' = {
  name: accountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    capabilities: [{ name: 'EnableServerless' }]
  }
}

resource database 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2023-04-15' = {
  parent: cosmosAccount
  name: 'UserActivityDb'
  properties: { resource: { id: 'UserActivityDb' } }
}

resource container 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2023-04-15' = {
  parent: database
  name: 'UserActivityLog'
  properties: {
    resource: {
      id: 'UserActivityLog'
      partitionKey: { paths: ['/UserId'], kind: 'Hash' }
    }
  }
}
```


# Infrastructure as Code (IaC) & Cloud Deployment Cheat Sheet

## 1. Cloud Service Provider Equivalents

### Primary Hyperscalers
| Cloud Service Provider (CSP) | Native IaC Engine | Modern Native Language / Abstraction | Template Format | Native Managed Deployment Service |
| :--- | :--- | :--- | :--- | :--- |
| **Amazon Web Services (AWS)** | **AWS CloudFormation** | **AWS CDK** *(compiles to CloudFormation)* | YAML / JSON | CloudFormation Stacks / AWS SAM |
| **Microsoft Azure** | **Azure Resource Manager (ARM)** | **Azure Bicep** *(compiles to ARM JSON)* | JSON / Bicep Syntax | Azure Resource Manager Deployments |
| **Google Cloud Platform (GCP)** | **Google Cloud Infrastructure Manager** | **Deployment Manager** *(legacy)* | YAML / HCL (Terraform) | GCP Infrastructure Manager / Cloud Build |

### Secondary & Enterprise Cloud Providers
| Cloud Service Provider (CSP) | Native IaC Engine / Service | Template Format / DSL | Deployment Mechanics |
| :--- | :--- | :--- | :--- |
| **Oracle Cloud Infrastructure (OCI)** | **OCI Resource Manager** | HCL (Terraform-native) | Native engine executes Terraform configurations. |
| **Alibaba Cloud** | **Resource Orchestration Service (ROS)** | JSON / YAML / **ROS CDK** | CloudFormation-like declarative syntax. |
| **IBM Cloud** | **IBM Cloud Schematics** | HCL (Terraform) / Ansible | Native SaaS wrapper for Terraform & Ansible. |
| **Huawei Cloud** | **Resource Template Service (RTS)** | YAML / JSON | Declarative stack orchestration engine. |

---