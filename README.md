# EBS Snapshot Backup and Restore – Manual Disaster Recovery on AWS

**A hands-on exercise in point-in-time backup and volume recovery on AWS — executing every step manually through the AWS Console and Linux CLI to build a solid mental model of how EBS snapshots work before moving to automation.**

![AWS](https://img.shields.io/badge/AWS-EC2%20%7C%20EBS-orange)
![Region](https://img.shields.io/badge/Region-ap--south--1%20(Mumbai)-blue)
![Linux](https://img.shields.io/badge/OS-Amazon%20Linux%202023-red)
![Workflow](https://img.shields.io/badge/Workflow-Manual-lightgrey)
![Cost](https://img.shields.io/badge/Cost-Free%20Tier-brightgreen)

---

## Objective

Back up an EC2 instance's root EBS volume using a manual snapshot, restore it to a new volume, attach it to the same instance, and verify that the original data is fully intact — simulating a real-world volume recovery scenario from scratch.

---

## Scenario

Imagine a production EC2 instance whose root volume gets corrupted overnight. Before thinking about automation or disaster recovery pipelines, a cloud engineer must first deeply understand the manual recovery process — what each step does, why the order matters, and what can go wrong.

This project simulates exactly that. A test EC2 instance was set up, data was written to its root EBS volume, a snapshot was taken as a backup, and a full restore was performed on a new volume — all manually, one step at a time, through the AWS Console and EC2 Instance Connect terminal.

> Coming from a GCP background, this project also served as a practical mapping exercise:
> Persistent Disk → EBS, Disk Snapshot → EBS Snapshot, Firewall Rules → Security Groups, one-click SSH → EC2 Instance Connect.

---

## Architecture

```
┌─────────────────────────────────────────────┐
│         EC2 Instance (t3.micro)             │
│         Amazon Linux 2023 | ap-south-1a     │
│                                             │
│   Root EBS Volume (nvme0n1)                 │
│   vol-0b0cc792fa5627484 | 8 GiB gp3        │
│   Mounted at: /                             │
│   Contains: /home/ec2-user/testfile.txt     │
└──────────────────┬──────────────────────────┘
                   │
                   │ Step 1: Snapshot created
                   ▼
┌─────────────────────────────────────────────┐
│         EBS Snapshot (completed)            │
│         Point-in-time backup of root volume │
│         Stored internally by AWS in S3      │
└──────────────────┬──────────────────────────┘
                   │
                   │ Step 2: New volume created from snapshot
                   ▼
┌─────────────────────────────────────────────┐
│      Restored EBS Volume (nvme1n1)          │
│      vol-021d9e9913a8bde24 | 8 GiB gp3     │
│      Same AZ: ap-south-1a (mandatory)       │
└──────────────────┬──────────────────────────┘
                   │
                   │ Step 3: Attached to EC2 as /dev/sdf
                   ▼
┌─────────────────────────────────────────────┐
│      Mounted at /mnt/restored               │
│      Data verified: testfile.txt intact ✅  │
└─────────────────────────────────────────────┘
```

---

## Tools & Services

| Tool / Service | Purpose |
|---|---|
| AWS EC2 (t3.micro) | Virtual machine to attach and test volumes |
| AWS EBS (gp3) | Block storage volumes — original and restored |
| EBS Snapshots | Point-in-time backup mechanism |
| EC2 Instance Connect | Browser-based SSH — no local key management needed |
| Amazon Linux 2023 | OS on EC2; uses XFS filesystem by default |
| Linux CLI | `lsblk`, `mount`, `umount`, `file`, `cat`, `df` |

---

## Infrastructure Details

| Resource | Value |
|---|---|
| Instance Name | ebs-snapshot-restore |
| Instance Type | t3.micro (Free Tier in ap-south-1) |
| AMI | Amazon Linux 2023 |
| Availability Zone | ap-south-1a |
| Original Volume ID | vol-0b0cc792fa5627484 |
| Restored Volume ID | vol-021d9e9913a8bde24 |
| Volume Type | gp3, 8 GiB |
| Device Name (Restored) | /dev/sdf → nvme1n1 (NVMe naming on t3) |

---

## Step-by-Step Workflow

All steps were performed manually and in order. The sequence matters — each step is a prerequisite for the next.

---

### Step 1 — Launch EC2 and Write Test Data

**In AWS Console:**
- Launched a t3.micro EC2 instance named `ebs-snapshot-restore` with Amazon Linux 2023 in `ap-south-1a`
- Connected via EC2 Instance Connect (browser-based terminal — no .pem file management needed)

**In terminal:**
```bash
# Write a uniquely timestamped string to the root EBS volume
echo "This is my EBS snapshot test data. Created on: $(date)" > /home/ec2-user/testfile.txt

# Verify it saved correctly
cat /home/ec2-user/testfile.txt
```

**Why this step:** The test file is our ground truth. Its presence on the restored volume later is the proof that the snapshot captured the data correctly and the restore succeeded.

📸 `screenshots/01-ec2-running.png`

---

### Step 2 — Identify the Attached EBS Volume

**In AWS Console:**
- Navigated to EC2 → Instance → Storage tab
- Noted the root volume ID: `vol-0b0cc792fa5627484`
- Confirmed AZ: `ap-south-1a` — critical for later

**In terminal:**
```bash
# List all block devices and their mount points
lsblk

# Check current disk usage
df -h
```

**Output of lsblk:**
```
NAME          MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
nvme0n1       259:0    0   8G  0 disk
├─nvme0n1p1   259:1    0   8G  0 part /
├─nvme0n1p127 259:2    0   1M  0 part
└─nvme0n1p128 259:3    0  10M  0 part /boot/efi
```

**Why this step:** Before snapshotting, confirm which volume is attached and note its exact AZ. A restored volume can only attach to an EC2 instance in the same AZ — getting this wrong in Task 3 means the attach will fail entirely.

> **Note on NVMe naming:** t3.micro uses NVMe-based storage, so volumes appear as `nvme0n1` instead of `xvda` (which t2.micro uses). Same concept — just newer, faster hardware with different naming.

📸 `screenshots/02-ebs-volume-identified.png`

---

### Step 3 — Create an EBS Snapshot

**In AWS Console:**
- EBS → Volumes → selected root volume → Actions → Create Snapshot
- Description: `Backup of ebs-snapshot-restore root volume`
- Tag: `Name = ebs-snapshot-restore-backup`
- Waited for status: `pending` → `completed`

**Why this step:** The snapshot is the backup — a point-in-time, read-only copy of the entire volume stored internally by AWS in S3. It captures everything on the disk at that exact moment, including our `testfile.txt`. Snapshots are incremental after the first one, meaning only changed blocks are stored — making them cost-efficient for regular backups.

> A `pending` snapshot is still being written. Never create a volume from a pending snapshot — it may result in incomplete or corrupted data.

📸 `screenshots/03-snapshot-created.png`

---

### Step 4 — Create a New Volume from the Snapshot

**In AWS Console:**
- EBS → Snapshots → selected snapshot → Actions → Create volume from snapshot
- Volume type: `gp3`
- Size: `8 GiB`
- **Availability Zone: `ap-south-1a`** ← must match the EC2 instance's AZ
- Tag: `Name = ebs-restored-volume`
- Waited for status: `available`

**Why this step:** This is the restore step. AWS reads the snapshot data and creates a brand new, independent EBS volume that is an exact copy of the original at the time the snapshot was taken. Status `available` means the volume exists but isn't attached to any instance yet — like a hard drive sitting on a desk, not plugged in.

> **Critical:** EBS volumes are AZ-specific. A volume in `ap-south-1b` cannot attach to an EC2 in `ap-south-1a`. Always verify the AZ before creating the volume.

📸 `screenshots/04a-new-volume-from-snapshot.png`

---

### Step 5 — Attach the Restored Volume to EC2

**In AWS Console:**
- EBS → Volumes → selected `ebs-restored-volume` → Actions → Attach volume
- Instance: `ebs-snapshot-restore`
- Device name: `/dev/sdf`
- Status changed: `available` → `in-use`

**Why this step:** Attaching the volume is the equivalent of plugging in an external hard drive. The OS doesn't automatically use it — it just detects it. The actual mounting (making it accessible via a folder) happens in the next step.

> AWS maps `/dev/sdf` to `/dev/nvme1n1` internally on NVMe-based instances (t3 family). This is just a naming translation — the device is the same.

📸 `screenshots/05a-volume-attached.png`

---

### Step 6 — Mount and Verify Restored Data

**In EC2 Instance Connect terminal:**

```bash
# Confirm both disks are now visible to the OS
lsblk
```

**Output:**
```
NAME          MAJ:MIN RM SIZE RO TYPE MOUNTPOINTS
nvme0n1       259:0    0   8G  0 disk
├─nvme0n1p1   259:1    0   8G  0 part /
├─nvme0n1p127 259:2    0   1M  0 part
└─nvme0n1p128 259:3    0  10M  0 part /boot/efi
nvme1n1       259:4    0   8G  0 disk         ← restored volume detected
├─nvme1n1p1   259:5    0   8G  0 part
├─nvme1n1p127 259:6    0   1M  0 part
└─nvme1n1p128 259:7    0  10M  0 part
```

```bash
# Check the filesystem type on the restored volume
sudo file -s /dev/nvme1n1p1
# Output: SGI XFS filesystem data (blksz 4096, inosz 512, v2 dirs)

# Create a mount point directory
sudo mkdir /mnt/restored

# Mount with XFS type and nouuid flag (explained below)
sudo mount -t xfs -o nouuid /dev/nvme1n1p1 /mnt/restored

# Verify the test data from Step 1 is present
cat /mnt/restored/home/ec2-user/testfile.txt
# Output: This is my EBS snapshot test data. Created on: Wed May 27 14:03:13 UTC 2026

# Confirm mount in disk usage
df -h
```

**Why `nouuid`:** XFS filesystems store a UUID (unique identifier) to distinguish themselves. Since the restored volume is a clone of the original snapshot, both volumes share the exact same UUID. When Linux detects two mounted XFS filesystems with identical UUIDs, it refuses to mount the second one to prevent confusion. The `nouuid` flag instructs the mount command to skip UUID validation and mount the volume regardless. This is a known and expected challenge when working with XFS snapshots.

✅ Seeing `testfile.txt` with the original timestamp confirms the snapshot captured the data correctly and the restore succeeded completely.

📸 `screenshots/06a-data-verified.png`  
📸 `screenshots/06b-data-verified-mount.png`

---

### Step 7 — Cleanup All Resources

Always clean up after a practice project — leaving resources running wastes Free Tier hours and, after the Free Tier period, incurs real charges.

**In terminal (first):**
```bash
# Always unmount before detaching — like safely ejecting a USB drive
sudo umount /mnt/restored
```

**In AWS Console (in this exact order):**

1. **Detach restored volume:** EBS → Volumes → `ebs-restored-volume` → Actions → Detach Volume → wait for `available`
2. **Delete restored volume:** Actions → Delete Volume → confirm
3. **Delete snapshot:** EBS → Snapshots → `ebs-snapshot-restore-backup` → Actions → Delete Snapshot → confirm
4. **Terminate EC2:** Instances → `ebs-snapshot-restore` → Instance State → Terminate Instance → confirm

> **Terminate, not Stop:** Stopping an EC2 halts the compute but keeps the EBS root volume running — you still pay for storage. Terminating deletes the instance and its root volume entirely. For practice projects with no data to preserve, always terminate.

📸 `screenshots/07a-cleanup-instance.png`  
📸 `screenshots/07b-cleanup-volumes.png`  
📸 `screenshots/07c-cleanup-snapshots.png`

---

## Key Engineering Learnings

**1. AZ-Locked Recovery**  
EBS volumes exist within a single Availability Zone and cannot cross AZ boundaries. The restored volume must always be created in the same AZ as the target EC2 instance. In a real AZ failure scenario, the snapshot would first need to be copied to another AZ (or region) before a new volume could be created there.

**2. XFS UUID Collision**  
When a volume is created from a snapshot, the cloned XFS filesystem inherits the same UUID as the original. Linux refuses to mount a second XFS volume with a duplicate UUID to prevent filesystem confusion. The `nouuid` mount option bypasses this check. In production, the correct long-term fix is to assign a new UUID using `xfs_admin -U generate /dev/nvme1n1p1` after mounting and before regular use.

**3. NVMe Device Naming on t3 Instances**  
Unlike t2.micro (which uses `xvda`, `xvdf` naming), t3.micro uses NVMe-based storage resulting in `nvme0n1`, `nvme1n1` device names. AWS maps the `/dev/sdf` device name used during volume attachment to `nvme1n1` internally. Always run `lsblk` after attaching a volume to confirm its actual device name before mounting.

**4. Snapshot Consistency**  
EBS snapshots are crash-consistent, meaning they capture the state of the disk as-is at that moment — equivalent to pulling the power plug cleanly. For databases or applications actively writing to disk, this could result in an inconsistent state. Application-consistent snapshots (which guarantee in-flight transactions are flushed) require a pre-snapshot quiesce step using `fsfreeze` or database-native flush commands.

**5. Unmount Before Detach**  
Detaching a volume from the AWS Console while it is still mounted in Linux is the cloud equivalent of yanking a USB drive mid-write. The OS may still be flushing data, and forceful detachment can corrupt the filesystem. Always run `sudo umount` first, then detach from the console.

**6. Snapshots are Incremental**  
The first snapshot captures the full volume. Every subsequent snapshot only stores blocks that changed since the last snapshot. Deleting a snapshot only removes blocks that are not referenced by any other snapshot. This means older snapshots can sometimes be deleted without data loss — but AWS handles this de-duplication automatically.

---

## Command Reference

> `commands.sh` in this repository is **not an automation script** — it is a precise record of every Linux command executed during the process. It serves as personal documentation and a reference for building a proper automation script in the future.

See [`commands.sh`](./commands.sh)

---

## Project Structure

```
ebs-snapshot-restore/
├── README.md
├── commands.sh
└── screenshots/
    ├── 01-ec2-running.png
    ├── 02-ebs-volume-identified.png
    ├── 03-snapshot-created.png
    ├── 04-new-volume-from-snapshot.png
    ├── 04b-volumes-detail.png
    ├── 05-volume-attached.png
    ├── 05b-volume-attached-detail.png
    ├── 06-data-verified.png
    ├── 06b-data-verified-mount.png
    ├── 07-cleanup-instance.png
    ├── 07b-cleanup-volumes.png
    └── 07c-cleanup-snapshots.png
```

---

## Future Scope

This project was intentionally kept manual to build foundational understanding. The next iterations would include:

- **Automation:** Convert `commands.sh` into a robust bash script using the AWS CLI — including `aws ec2 wait snapshot-completed` to handle async operations properly
- **Infrastructure as Code:** Rebuild the environment using Terraform — EC2, EBS volumes, security groups, and snapshot lifecycle policies defined as code
- **Lifecycle Management:** Use AWS Data Lifecycle Manager (DLM) to automatically schedule daily snapshots and expire old ones
- **Application-Consistent Snapshots:** Integrate `fsfreeze` before snapshotting to guarantee database-safe backups
- **Cross-Region Disaster Recovery:** Copy snapshots to a second region (ap-southeast-1) and automate standby instance creation
- **UUID Fix on Restore:** Automate UUID reassignment on restored XFS volumes using `xfs_admin` to eliminate the `nouuid` workaround

---

## Outcome

Successfully performed a complete manual EBS backup and restore cycle on AWS. The original test data written to the root volume was fully recovered from the snapshot onto a new volume, verified on the filesystem, and every resource was cleanly removed after the exercise. This project established a clear mental model of how AWS block storage, snapshots, and volume recovery work at a fundamental level — and identified the exact edge cases (UUID conflicts, NVMe naming, AZ constraints) that automation must handle. ✅