##### Git-Driven Automation vs GitOps

Git-Driven Automation vs. GitOps
Core Terminology
- Event-Driven CI/CD (Git-Driven): Webhooks listen for Git events (`push`, `pull_request`, `merge`) to automatically kick off pipelines (GitHub Actions, GitLab CI, AWS CodePipeline). The pipeline executes imperative scripts or build tasks to push changes out.

- GitOps: A subset of practices requiring a declarative desired state stored in Git, combined with an automated reconciliation loop (e.g., Argo CD, Flux) that continuously pulls changes and corrects drift.

##### AWS Context
• VCS: AWS CodeCommit (or GitHub/GitLab integrated via Amazon EventBridge).

• Pipelines: AWS CodePipeline triggers AWS CodeBuild and CodeDeploy upon receiving repository events.


###### CICD vs Gitops

1. Traditional CI/CD (Event-Driven, Not GitOps)
How it works: A webhook fires on a git push or pull request, triggering Jenkins, GitHub Actions, GitLab CI, or AWS CodePipeline to build, test, and push/deploy the application (e.g., running kubectl apply or executing an imperative script to update servers).

    *Why it's not GitOps*: The pipeline acts as an active agent that pushes changes out to the environment. If someone manually changes something on the server or in the cluster, the system doesn't automatically revert it. The code in Git tells the pipeline what actions to perform.

2. GitOps (Declarative State + Pull-Based Reconciliation)
How it works: The environment state is defined declaratively in a Git repository (e.g., Kubernetes manifests, Terraform configs). Tools like Argo CD or Flux live inside the target environment, constantly watching that Git repo. When a merge happens, the agent pulls the changes and continuously reconciles the cluster to match that desired state.

    *Why it is GitOps*: The infrastructure or application state is entirely derived from Git, and an internal controller ensures drift is automatically corrected.