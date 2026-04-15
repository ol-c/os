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
}
