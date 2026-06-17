# History Notes

The original project grew out of a live Android Wayland, Steam, Gamescope, and
driver debugging session on one phone and one Linux rootfs. This public tree is
the cleanup pass:

- package the Android display app source,
- name files after what they do,
- remove one-container assumptions,
- keep Droidspaces as an optional adapter,
- preserve the dmabuf/Vulkan/SurfaceControl goal,
- provide repeatable install scripts for Termux, proot, chroot, and LXC.

Old logs, private driver packages, game data, and one-machine shell scripts
should stay out of this repository.
