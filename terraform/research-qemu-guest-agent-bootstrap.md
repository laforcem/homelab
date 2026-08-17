# Research: bootstrapping qemu-guest-agent for Terraform-managed Proxmox VMs

## 1. Problem restated

VMs are cloned from a Debian 13 "generic" cloud image (`https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2`), downloaded with `proxmox_download_file`/`proxmox_virtual_environment_download_file` and imported as a `proxmox_virtual_environment_vm` template. Cloned VMs set `agent { enabled = true }` so Terraform can read `ipv4_addresses` and use the agent for graceful shutdown. Debian's generic/genericcloud images deliberately don't ship `qemu-guest-agent`, so right after a fresh clone every `plan`/`apply`/`destroy` blocks for the full `agent.timeout` (default 15m) while Terraform's state refresh tries to reach an agent that isn't running. A custom cloud-init snippet was tried and abandoned because `content_type = "snippets"` uploads require an `ssh` block on the *provider* (separate SSH+sudo credentials to the Proxmox node) — the REST API doesn't support uploading arbitrary snippet files, so the provider SSHes into the node to write them. That felt like disproportionate new infrastructure for this problem, given an Ansible role is already planned to handle OS baseline config (including installing the agent) after Terraform runs.

---

## 2. Approach 1 — Packer-based image baking

**What it is:** Use HashiCorp Packer with the Proxmox builder (`proxmox-iso` or `proxmox-clone` plugin) to boot the cloud image, run provisioners (shell/ansible) to install `qemu-guest-agent` and any baseline packages, then convert the result to a Proxmox template — before Terraform ever touches it.

**Primary sources:**
- HashiCorp Packer Proxmox builder docs (https://developer.hashicorp.com/packer/integrations/hashicorp/proxmox/latest/components/builder/iso): the builder has a `qemu_agent` option (defaults to `true`) that enables the QEMU agent device on the VM; the docs note that when enabled, `qemu-guest-agent` **must be installed on the guest**, and that Packer itself relies on the guest agent to retrieve the VM's IP for its own SSH/WinRM communicator step — without it, Packer's own build can stall the same way Terraform does.
- Community write-ups (runtimeterror.dev "Building Proxmox Templates with Packer", multiple dev.to posts) show the common pattern: cloud-init `packages: [qemu-guest-agent]` + `runcmd` inside the Packer build's cloud-init snippet, so the agent is installed and running by the time Packer converts the VM to a template.

**Tradeoffs:**
- Solves the problem cleanly and permanently — every template that comes out of the pipeline already has the agent running, so Terraform never faces the chicken-and-egg situation.
- But it's a second tool with its own credentials, its own build pipeline, and its own state to keep in sync with Terraform (image versioning, rebuild cadence). It duplicates work the planned Ansible role will already do (install baseline packages) — you'd effectively be provisioning the box twice, once in Packer and once in Ansible.
- Packer itself needs the guest agent (or a network-reachable IP by other means) to complete its own build, so it doesn't remove the underlying "how does automation learn the VM's IP before the agent exists" problem — it just relocates it to a one-time build step instead of every `terraform apply`.

**How common:** Very common in the broader "Infra as Code on Proxmox" community (multiple independent blog posts describe the same pattern), but it's aimed at teams that want reproducible golden images and are willing to run a Packer pipeline continuously. For homelab-scale personal setups it appears frequently as a "next step" once someone is unhappy with clone-then-fix-up templates, not as the very first thing people reach for.

---

## 3. Approach 2 — `virt-customize`/`virt-sysprep` (libguestfs tools) on the downloaded qcow2

**What it is:** Before importing the qcow2 as a Proxmox template, customize it offline with `virt-customize -a <file>.qcow2 --install qemu-guest-agent` (from the `libguestfs-tools` package), then typically clear the machine-id with `virt-customize -a <file>.qcow2 --run-command "echo -n > /etc/machine-id"`. This operates on the local disk image file directly, not via the Proxmox API or an SSH session into the node's shell for Terraform's purposes — it's a manual/scripted step that happens before `terraform apply` ever runs.

**Primary sources:**
- Community practitioner write-ups describing this exact recipe (totaldebug.uk-style walkthrough): "The qemu-guest-agent is not installed on the cloud-images, so we need a way to inject that into our image file. This can be done with a great tool called `virt-customize`."
- Proxmox community forum thread, "`virt-customize` does not install qemu-guest-agent on qcow2 image" (https://forum.proxmox.com/threads/virt-customize-does-not-install-qemu-guest-agent-on-qcow2-image.166115/): a user ran `virt-customize -a debian-12-generic-amd64.qcow2 --install qemu-guest-agent`, the command reported success ("Finishing off", no errors), but the resulting VM had no `qemu-guest-agent` unit at all. Forum moderators note `virt-customize` is a third-party libguestfs tool, not something Proxmox itself supports, and the thread closes **without a definitive root cause** — the failure was not explained, and community members instead suggested falling back to installing the agent on a running VM or via cloud-init/Ansible.

**Tradeoffs:**
- In principle it sidesteps the SSH+sudo provider-block requirement entirely, since it touches the local file, not the Proxmox REST API or node shell.
- But the one primary source found that actually tried it hit a real, unresolved failure — `virt-customize` reported success while the package silently didn't end up in the image. That's a meaningful reliability red flag for a Debian 13/trixie image specifically (the forum thread is Debian 12, and trixie is newer still); it would need to be verified working before being trusted, not assumed.
- Requires `libguestfs-tools` installed somewhere (locally or on the Proxmox host) and adds an extra offline-image-editing step outside both Terraform and the planned Ansible role — a third place configuration happens, which cuts against the "Ansible does OS baseline" separation of concerns already decided.

**How common:** Documented in a handful of practitioner blogs as a known technique for Proxmox cloud-image templates, but not the dominant pattern — most write-ups instead go for the cloud-init vendor/user-data route (Approach 3) or Packer (Approach 1). The one forum thread specifically testing it on a Debian generic image failed, which is a caution flag rather than an endorsement.

---

## 4. Approach 3 — bpg/proxmox provider's own documented approach (cloud-init guide, snippets requirement, alternatives)

**Primary sources:**
- `docs/guides/cloud-init.md` (https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/guides/cloud-init.md): the guide's own recommended pattern for the agent is a cloud-config snippet with
  ```
  packages:
    - qemu-guest-agent
    - net-tools
    - curl
  runcmd:
    - systemctl enable qemu-guest-agent
    - systemctl start qemu-guest-agent
  ```
  uploaded via `proxmox_virtual_environment_file` with `content_type = "snippets"`, referenced by `initialization.user_data_file_id` — i.e. exactly the approach already tried and abandoned in this repo. The guide explicitly flags that the "Snippets" content type must be enabled on the target datastore.
- `docs/resources/virtual_environment_file.md`: confirms the SSH requirement directly — "The resource with this content type uses SSH access to the node. You might need to configure the `ssh` option in the `provider` section." It also states that `iso`, `vztmpl`, and `import` content types **always use the HTTP API** and do not need SSH — but none of those content types are for cloud-init snippet YAML, so this doesn't offer an escape hatch for this specific use case. There is also an `upload_mode` argument (`stream`, the default, uses SSH; `sftp`, which needs direct write permission without invoking sudo) — both still require SSH connectivity to the node, just with different transport/permission mechanics. So there is no documented way to upload a snippet through the API alone; the SSH+sudo requirement is confirmed, not avoidable, for this content type.
- `docs/resources/virtual_environment_vm.md` (https://github.com/bpg/terraform-provider-proxmox/blob/main/docs/resources/virtual_environment_vm.md): agent block schema — `timeout` "The maximum amount of time to wait for data from the QEMU agent to become available" defaults to `"15m"`. The doc also carries an explicit warning: "Do **not** run VM with `agent.enabled = true`, unless the VM is configured to automatically **start** `qemu-guest-agent` at some point," and notes the provider "has no way to distinguish between 'qemu-guest-agent not installed' and 'very long boot due to a disk check'" — it trusts `agent.enabled` and waits the full timeout regardless.
- GitHub Issue #669, "Bunch of (possible) problems with qemu-guest-agent" (https://github.com/bpg/terraform-provider-proxmox/issues/669): reports the exact symptom in this repo's problem statement — `agent.enabled = true` with no agent installed causes `plan`/`apply` and the `proxmox_virtual_environment_vms` data source to hang for the full timeout, and `reboot = true` with a missing agent fails with "context deadline exceeded." The reporter's own proposed mitigations are to shorten/zero the timeout or make Stop/Start (ACPI) the fallback instead of Reboot/Shutdown when the agent is absent — no maintainer-endorsed fix is recorded in the fetched content.
- Practitioner write-up (trfore, "Provisioning Proxmox 8 VMs with Terraform and BPG", https://www.trfore.com/posts/provisioning-proxmox-8-vms-with-terraform-and-bpg/): builds the template as a **separate, manual/scripted step outside Terraform** — SSH into the Proxmox node directly (`ssh root@pve`), hand-write the vendor-data snippet straight onto the node's filesystem (`/var/lib/vz/snippets/vendor-data.yaml`) with a heredoc, then build the template with a small shell script wrapping `qm` commands. This is a variant of Approach 3: it uses the same cloud-init-vendor-file idea the bpg guide recommends, but does the snippet placement as a one-time manual template-prep step (plain `ssh`/`qm`), never asking Terraform's `proxmox_virtual_environment_file` resource to manage it — so it never needs the provider's `ssh` block at all. The tradeoff is that template creation then lives outside Terraform's state entirely, as an imperative script.

**Tradeoffs:** The maintainer-documented path is exactly the one already tried and rejected here (snippet + provider `ssh` block). The only way to use cloud-init-vendor-file content *without* configuring the provider `ssh` block, per bpg's own docs, is to place the snippet file on the node by some other means (manually, via a provisioning script, via Ansible/SCP) and reference it by its already-existing node path — Terraform would then just point `user_data_file_id`/`vendor_data_file_id` at a pre-existing file rather than uploading it itself. That's a legitimate middle ground: it keeps the "install agent via cloud-init on first boot" idea, but moves the file-placement step to whatever tool already needs node access (which, per the plan here, would end up being Ansible or a manual step, not Terraform).

**How idiomatic:** This is the provider's own first-party recommended pattern, so it's clearly considered idiomatic by the maintainer — but it was already tried and found to require infrastructure (SSH+sudo provider credentials) disproportionate to the problem, which is a legitimate judgment call given the separate Ansible plan, not a misreading of the docs.

---

## 5. Approach 4 — tolerate the timeout, let Ansible install the agent later

**What it is:** Set `agent.timeout` low (seconds, not the 15m default) and accept that `ipv4_addresses` and other agent-derived attributes are unknown/stale until Ansible installs and starts `qemu-guest-agent` in a later run. Terraform's job stays "provision the VM," Ansible's stays "configure the OS," including the agent.

**Primary sources:**
- `virtual_environment_vm.md` confirms `agent.timeout` is a plain, user-settable duration string defaulting to `"15m"` — nothing in the schema prevents setting it to `"5s"` or similar; it's an ordinary Terraform timeout knob, not a fixed platform behavior.
- GitHub Issue #669 (above) is effectively other operators proposing exactly this — the reporter argues the timeout should default lower (values as low as `0s`/`1s` are suggested) specifically because waiting 15 minutes for an agent that legitimately won't exist yet is bad UX. No maintainer response endorsing a specific default was found in the fetched thread content, so treat "shrink the timeout" as a community-proposed workaround rather than an officially blessed pattern — but it directly matches the schema's documented behavior (the timeout is just how long the provider is willing to wait, no more).
- Discussion #1037, "Timeout adjustments" (https://github.com/bpg/terraform-provider-proxmox/discussions/1037): confirms the provider has more than one independently configurable timeout (e.g. `timeout_create` on the container resource, and by extension the analogous per-operation timeouts on the VM resource), and the maintainer's guidance there was simply to point at the existing documented timeout arguments — i.e. "yes, these are configurable, read the docs" rather than a recommendation for what value to use.

**Tradeoffs:**
- Cheapest possible fix: a one-line config change (`agent.timeout = "5s"` or similar), no new tooling, no new credentials.
- Cost: `ipv4_addresses` and other agent-derived computed attributes will be empty/stale on a fresh clone until Ansible runs and the agent starts — anything depending on them in the same `apply` (e.g. outputs consumed immediately by Ansible dynamic inventory) needs another IP-discovery path in the interim (e.g. a static/DHCP-reserved IP set via cloud-init network-config, which this repo's VLAN/static-IP conventions may already support).
- Does not remove the underlying warning in the docs that `agent.enabled = true` with no agent running makes `Reboot`/`Shutdown` operations fail outright (not just slow) — so a short timeout mitigates the *wait*, but a `destroy` or forced reboot before Ansible has run could still hit a hard failure, worth testing deliberately.

**How idiomatic:** Nothing in the fetched primary sources frames this as an official "best practice," but it's a direct, mechanical use of a documented, user-facing setting, and it's the natural complement to a deliberate Terraform/Ansible split — provisioning tools that don't wait around for configuration-management concerns are a normal pattern in general (not Proxmox-specific), just not something the bpg docs spell out as a named strategy.

---

## 6. Approach 5 — Proxmox's own official Cloud-Init template tutorial

**Primary source:** Proxmox wiki, "Cloud-Init Support" (https://pve.proxmox.com/wiki/Cloud-Init_Support).

**What it says:** The page's template-preparation walkthrough covers importing/downloading a cloud image, attaching a Cloud-Init drive (`qm set 9000 --ide2 local-lvm:cloudinit`), setting boot order, configuring a serial console, and converting to a template (`qm template 9000`). **It does not mention `qemu-guest-agent` anywhere** — no installation step, no warning about cloud images lacking it, no recommendation. The page does state a general preference: "We usually recommend to prepare the images by yourself" rather than relying purely on downloaded cloud images as-is, which is a loose endorsement of *some* form of image customization (consistent with Approaches 1/2/3) but stops short of naming a specific method or addressing the agent at all.

**Takeaway:** Proxmox's own tutorial simply doesn't engage with this problem — the guest agent question is left entirely to the user's distro/image choice and downstream tooling. This confirms the gap is real and not something Proxmox considers its own responsibility to solve in the base template-creation workflow.

**Also verified — why Debian excludes the agent:** Debian Wiki, "Cloud" (https://wiki.debian.org/Cloud): "qemu-guest-agent assumes a level of integration between the VM and the underlying infrastructure that is not appropriate for a general purpose image" — this is why it's excluded from both `generic` and `genericcloud` variants (which otherwise differ only in kernel build, not package set).

---

## 7. Recommendation for this homelab

Given the stated context — hand-writing Terraform deliberately for interview-prep familiarity, not memory/compute constrained, and an Ansible role already planned to own OS baseline config including the agent — **Approach 4 (shrink `agent.timeout`, let Ansible install the agent) is the best fit**, with a note on IP discovery:

- It requires no new tooling investment (no Packer pipeline, no libguestfs step, no provider `ssh`/sudo credentials) — all of which would be real infrastructure to learn and maintain for a problem that's really just "the agent isn't there yet, and that's expected."
- It keeps the Terraform/Ansible boundary exactly where it was already decided: Terraform provisions and hands off; Ansible configures, including `qemu-guest-agent`. Blurring that boundary to solve a cosmetic wait-time problem (via Packer or SSH-snippet-upload) would add tooling surface without teaching anything more about Terraform itself — if anything, standing up Packer or the provider's `ssh` block right now is *scope creep* relative to the actual learning goal.
- Approach 2 (`virt-customize`) is explicitly not recommended: the one primary source that tested it against a Debian generic-family image hit an unexplained silent failure. It would need real verification against Debian 13 specifically before being trusted, and even if it worked, it plants a third place (outside Terraform, outside Ansible) where the box gets configured — worth avoiding on separation-of-concerns grounds alone.
- Packer (Approach 1) is the right *eventual* answer if/when this setup outgrows "learning Terraform in a homelab" — e.g. once template rebuild cadence, multiple base images, or CI-driven image builds become real needs — but it's disproportionate today, and it doesn't even fully remove the underlying IP-discovery problem (Packer needs the same agent to complete its own build).
- One thing worth doing regardless of timeout tuning: check whether `agent.enabled = true` combined with a short timeout still causes hard failures (not just slow waits) on `Reboot`/`Shutdown`/`destroy` before Ansible has run — the bpg docs' warning on this point is unambiguous, and it's worth deliberately testing a `terraform destroy` against a fresh, agent-less clone to see whether it hangs, fails, or degrades gracefully to ACPI, rather than assuming a short timeout alone is sufficient.

**Top recommendation summary:** Shrink `agent.timeout` to a short value (e.g. a few seconds) and accept `ipv4_addresses` is unknown until Ansible installs the agent — this matches the deliberate Terraform/Ansible split already in place, needs no new tooling or credentials, and is the most Terraform-education-relevant path (it's just a resource-attribute tradeoff to understand, not a new pipeline to operate). Avoid `virt-customize` for now (unverified/failed on a similar Debian image in the one primary source found); treat Packer as a good future step once the lab outgrows single-template needs, not a now-step.
