{ ... }:

{
  boot.supportedFilesystems = [ "virtiofs" ];

  fileSystems."/source" = {
    device = "ol-c-source";
    fsType = "virtiofs";
    options = [
      "rw"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
    ];
  };

  fileSystems."/vm-images" = {
    device = "ol-c-vm-images";
    fsType = "virtiofs";
    options = [
      "ro"
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=60"
    ];
  };
}
