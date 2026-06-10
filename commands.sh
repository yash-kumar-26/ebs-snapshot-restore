#!/bin/bash
# ============================================================
# EBS Snapshot Restore - Manual Command Reference
# Author: Yash Kumar
#
# This file is NOT an automation script.
# It is a log of the exact commands I executed during the
# manual EBS snapshot backup & restore project.
#
# Console-only steps (not in this shell):
#   1. Created snapshot of root volume vol-0b0cc792fa5627484
#   2. Created new volume from snapshot in ap-south-1a
#   3. Attached the volume to the instance as /dev/sdf
# ============================================================

# ---- Write test data (performed on original volume) ----
echo "This is my EBS snapshot test data. Created on: $(date)" > /home/ec2-user/testfile.txt
cat /home/ec2-user/testfile.txt

# ---- Identify original attached volumes ----
lsblk
df -h

# ---- After attaching restored volume (manually via Console) ----
lsblk   # You should now see nvme1n1

# ---- Check filesystem type on the new volume ----
# Required when mount fails — confirms XFS filesystem
# which needs explicit -t xfs and -o nouuid flags
sudo file -s /dev/nvme1n1p1

# ---- Create mount point ----
sudo mkdir -p /mnt/restored   # -p avoids error if it already exists

# ---- Mount restored volume (nouuid to handle duplicate XFS UUID) ----
sudo mount -t xfs -o nouuid /dev/nvme1n1p1 /mnt/restored

# ---- Verify restored data ----
cat /mnt/restored/home/ec2-user/testfile.txt
df -h

# ---- Cleanup: unmount before detaching in Console ----
sudo umount /mnt/restored