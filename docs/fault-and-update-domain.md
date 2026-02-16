## Fault domains (FDs):
It represent a group of VMs that share a common power source and network switch.
When a VM is provisioned and assigned to an availability set, it is hosted within an FD.Each availability set has either two or three FDs by 
default, depending on the Azure region. Some regions provide two, while others provide three FDs in an availability set. 
FDs are non-configurable by users. 
When multiple VMs are created, they are placed on separate FDs. If the number of VMs is more than the FDs, the additional VMs are placed on existing
FDs. For example, if there are five VMs, there will be FDs hosted on more than one VM. FDs are related to physical racks in the Azure datacenter. 
FDs provide high availability in the case of unplanned downtime due to hardware, power, and network failure. Since each VM is placed on
a different rack with different hardware, a different power supply, and a different network, other VMs continue running if a rack snaps off.

## update domain: 
An FD takes care of unplanned downtime, while an update domain handles downtime from planned maintenance.
Each VM is also assigned an update domain and all the VMs within that update domain will reboot together.
There can be as many as 20 update domains in a single availability set. Update domains are non-configurable by users. 
When multiple VMs are created, they are placed on separate update domains. If more than 20 VMs are provisioned on an availability set, 
they are placed in a round‑robin fashion on these update domains. Update domains take care of planned maintenance. 
From Service Health in the Azure portal, you can check the planned maintenance details and set alerts.