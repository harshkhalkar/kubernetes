# Cluster Setup Scripts

This repository contains shell scripts for setting up a basic clustered environment. The scripts are designed to be used in a Linux-based environment to configure common settings and initialize a master node.

## Contents

- `setup-common.sh`: Configures common system settings required across all nodes.
- `setup-master.sh`: Sets up the master node of the cluster.

## System Requirements

**Master Node:**
- Minimum **2 GB RAM**
- Minimum **2 vCPU**
- Supported OS: Ubuntu (or other compatible Linux distributions)

> Ensure system meets these minimum requirements to avoid installation and performance issues.

## Usage

Make the scripts executable and run them in the required order:

```bash
chmod +x setup-common.sh setup-master.sh
./setup-common.sh
./setup-master.sh
```
