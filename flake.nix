{
  description = "ol-c browser-first OS prototype";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs = { self, nixpkgs, ... }:
    let
      lib = nixpkgs.lib;
      system = "x86_64-linux";
      firefoxPackagedPatchDir = ./patches/firefox/packaged;
      firefoxPackagedPatchStack =
        map
          (name: firefoxPackagedPatchDir + "/${name}")
          (lib.filter
            (name:
              (builtins.readDir firefoxPackagedPatchDir)."${name}" == "regular"
              && lib.hasSuffix ".patch" name)
            (builtins.attrNames (builtins.readDir firefoxPackagedPatchDir)));
      qemuInputPatch = builtins.toFile "qemu-vnc-hid-horizontal-wheel.patch" ''
        diff --git a/hw/input/hid.c b/hw/input/hid.c
        --- a/hw/input/hid.c
        +++ b/hw/input/hid.c
        @@ -151,6 +151,10 @@ static void hid_pointer_event(DeviceState *dev, QemuConsole *src,
                         e->dz--;
                     } else if (btn->button == INPUT_BUTTON_WHEEL_DOWN) {
                         e->dz++;
        +            } else if (btn->button == INPUT_BUTTON_WHEEL_LEFT) {
        +                e->pan--;
        +            } else if (btn->button == INPUT_BUTTON_WHEEL_RIGHT) {
        +                e->pan++;
                     }
                 } else {
                     e->buttons_state &= ~bmap[btn->button];
        @@ -207,6 +211,8 @@ static void hid_pointer_sync(DeviceState *dev)
                 }
                 prev->dz += curr->dz;
                 curr->dz = 0;
        +        prev->pan += curr->pan;
        +        curr->pan = 0;
             } else {
                 /* prepare next (clear rel, copy abs + btns) */
                 if (hs->kind == HID_MOUSE) {
        @@ -217,6 +223,7 @@ static void hid_pointer_sync(DeviceState *dev)
                     next->ydy = curr->ydy;
                 }
                 next->dz = 0;
        +        next->pan = 0;
                 next->buttons_state = curr->buttons_state;
                 /* make current guest visible, notify guest */
                 hs->n++;
        @@ -359,7 +366,7 @@ void hid_pointer_activate(HIDState *hs)

         int hid_pointer_poll(HIDState *hs, uint8_t *buf, int len)
         {
        -    int dx, dy, dz, l;
        +    int dx, dy, dz, pan, l;
             int index;
             HIDPointerEvent *e;

        @@ -383,9 +390,12 @@ int hid_pointer_poll(HIDState *hs, uint8_t *buf, int len)
             }
             dz = int_clamp(e->dz, -127, 127);
             e->dz -= dz;
        +    pan = int_clamp(e->pan, -127, 127);
        +    e->pan -= pan;

             if (hs->n &&
                 !e->dz &&
        +        !e->pan &&
                 (hs->kind == HID_TABLET || (!e->xdx && !e->ydy))) {
                 /* that deals with this event */
                 QUEUE_INCR(hs->head);
        @@ -394,6 +404,7 @@ int hid_pointer_poll(HIDState *hs, uint8_t *buf, int len)

             /* Appears we have to invert the wheel direction */
             dz = 0 - dz;
        +    pan = 0 - pan;
             l = 0;
             switch (hs->kind) {
             case HID_MOUSE:
        @@ -409,6 +420,9 @@ int hid_pointer_poll(HIDState *hs, uint8_t *buf, int len)
                 if (len > l) {
                     buf[l++] = dz;
                 }
        +        if (hs->protocol != 0 && len > l) {
        +            buf[l++] = pan;
        +        }
                 break;

             case HID_TABLET:
        @@ -431,6 +445,9 @@ int hid_pointer_poll(HIDState *hs, uint8_t *buf, int len)
                 if (len > l) {
                     buf[l++] = dz;
                 }
        +        if (len > l) {
        +            buf[l++] = pan;
        +        }
                 break;

             default:
        @@ -613,6 +630,7 @@ static const VMStateDescription vmstate_hid_ptr_queue = {
                 VMSTATE_INT32(xdx, HIDPointerEvent),
                 VMSTATE_INT32(ydy, HIDPointerEvent),
                 VMSTATE_INT32(dz, HIDPointerEvent),
        +        VMSTATE_INT32(pan, HIDPointerEvent),
                 VMSTATE_INT32(buttons_state, HIDPointerEvent),
                 VMSTATE_END_OF_LIST()
             }
        diff --git a/hw/usb/dev-hid.c b/hw/usb/dev-hid.c
        --- a/hw/usb/dev-hid.c
        +++ b/hw/usb/dev-hid.c
        @@ -93,7 +93,7 @@ static const USBDescIface desc_iface_mouse = {
                         0x00,          /*  u8  country_code */
                         0x01,          /*  u8  num_descriptors */
                         USB_DT_REPORT, /*  u8  type: Report */
        -                52, 0,         /*  u16 len */
        +                67, 0,         /*  u16 len */
                     },
                 },
             },
        @@ -100,7 +100,7 @@ static const USBDescIface desc_iface_mouse = {
                 {
                     .bEndpointAddress      = USB_DIR_IN | 0x01,
                     .bmAttributes          = USB_ENDPOINT_XFER_INT,
        -            .wMaxPacketSize        = 4,
        +            .wMaxPacketSize        = 5,
                     .bInterval             = 0x0a,
                 },
             },
        @@ -124,7 +124,7 @@ static const USBDescIface desc_iface_mouse2 = {
                         0x00,          /*  u8  country_code */
                         0x01,          /*  u8  num_descriptors */
                         USB_DT_REPORT, /*  u8  type: Report */
        -                52, 0,         /*  u16 len */
        +                67, 0,         /*  u16 len */
                     },
                 },
             },
        @@ -131,7 +131,7 @@ static const USBDescIface desc_iface_mouse2 = {
                 {
                     .bEndpointAddress      = USB_DIR_IN | 0x01,
                     .bmAttributes          = USB_ENDPOINT_XFER_INT,
        -            .wMaxPacketSize        = 4,
        +            .wMaxPacketSize        = 5,
                     .bInterval             = 7, /* 2 ^ (8-1) * 125 usecs = 8 ms */
                 },
             },
        @@ -153,7 +153,7 @@ static const USBDescIface desc_iface_tablet = {
                         0x00,          /*  u8  country_code */
                         0x01,          /*  u8  num_descriptors */
                         USB_DT_REPORT, /*  u8  type: Report */
        -                74, 0,         /*  u16 len */
        +                89, 0,         /*  u16 len */
                     },
                 },
             },
        @@ -183,7 +183,7 @@ static const USBDescIface desc_iface_tablet2 = {
                         0x00,          /*  u8  country_code */
                         0x01,          /*  u8  num_descriptors */
                         USB_DT_REPORT, /*  u8  type: Report */
        -                74, 0,         /*  u16 len */
        +                89, 0,         /*  u16 len */
                     },
                 },
             },
        @@ -473,6 +473,13 @@ static const uint8_t qemu_mouse_hid_report_descriptor[] = {
             0x75, 0x08,		/*     Report Size (8) */
             0x95, 0x03,		/*     Report Count (3) */
             0x81, 0x06,		/*     Input (Data, Variable, Relative) */
        +    0x05, 0x0c,		/*     Usage Page (Consumer Devices) */
        +    0x0a, 0x38, 0x02,	/*     Usage (AC Pan) */
        +    0x15, 0x81,		/*     Logical Minimum (-0x7f) */
        +    0x25, 0x7f,		/*     Logical Maximum (0x7f) */
        +    0x75, 0x08,		/*     Report Size (8) */
        +    0x95, 0x01,		/*     Report Count (1) */
        +    0x81, 0x06,		/*     Input (Data, Variable, Relative) */
             0xc0,		/*   End Collection */
             0xc0,		/* End Collection */
         };
        @@ -526,6 +534,13 @@ static const uint8_t qemu_tablet_hid_report_descriptor[] = {
             0x75, 0x08,		/*     Report Size (8) */
             0x95, 0x01,		/*     Report Count (1) */
             0x81, 0x06,		/*     Input (Data, Variable, Relative) */
        +    0x05, 0x0c,		/*     Usage Page (Consumer Devices) */
        +    0x0a, 0x38, 0x02,	/*     Usage (AC Pan) */
        +    0x15, 0x81,		/*     Logical Minimum (-0x7f) */
        +    0x25, 0x7f,		/*     Logical Maximum (0x7f) */
        +    0x75, 0x08,		/*     Report Size (8) */
        +    0x95, 0x01,		/*     Report Count (1) */
        +    0x81, 0x06,		/*     Input (Data, Variable, Relative) */
             0xc0,		/*   End Collection */
             0xc0,		/* End Collection */
         };
        diff --git a/include/hw/input/hid.h b/include/hw/input/hid.h
        --- a/include/hw/input/hid.h
        +++ b/include/hw/input/hid.h
        @@ -9,6 +9,7 @@
         typedef struct HIDPointerEvent {
             int32_t xdx, ydy; /* relative iff it's a mouse, otherwise absolute */
             int32_t dz, buttons_state;
        +    int32_t pan;
         } HIDPointerEvent;

         #define QUEUE_LENGTH    16 /* should be enough for a triple-click */
        diff --git a/ui/vnc.c b/ui/vnc.c
        --- a/ui/vnc.c
        +++ b/ui/vnc.c
        @@ -1791,6 +1791,8 @@ static void pointer_event(VncState *vs, int button_mask, int x, int y)
                 [INPUT_BUTTON_RIGHT]      = 0x04,
                 [INPUT_BUTTON_WHEEL_UP]   = 0x08,
                 [INPUT_BUTTON_WHEEL_DOWN] = 0x10,
        +        [INPUT_BUTTON_WHEEL_LEFT] = 0x20,
        +        [INPUT_BUTTON_WHEEL_RIGHT] = 0x40,
             };
             QemuConsole *con = vs->vd->dcl.con;
             int width = pixman_image_get_width(vs->vd->server);
      '';
      firefoxSourceOverlay = final: prev: {
        "firefox-unwrapped" = prev."firefox-unwrapped".overrideAttrs (old: {
          patches = (old.patches or []) ++ firefoxPackagedPatchStack;
        });
        firefox = final.wrapFirefox final.firefox-unwrapped { };
      };
      firefoxFastOverlay = import ./nix/firefox-localhost-fast.nix {
        firefoxPatches = firefoxPackagedPatchStack;
      };
      qemuInputOverlay = final: prev: {
        qemu_kvm = prev.qemu_kvm.overrideAttrs (old: {
          patches = (old.patches or []) ++ [ qemuInputPatch ];
        });
      };
      basePkgs = import nixpkgs {
        inherit system;
      };
      firefoxPkgs = import nixpkgs {
        inherit system;
        overlays = [ firefoxFastOverlay ];
      };
      firefoxSourcePkgs = import nixpkgs {
        inherit system;
        overlays = [ firefoxSourceOverlay ];
      };
      firefoxWasiSysRoot = firefoxSourcePkgs.runCommand "olc-firefox-source-wasi-sysroot" { } ''
        mkdir -p $out/lib/wasm32-wasi
        for lib in ${firefoxSourcePkgs.pkgsCross.wasi32.llvmPackages.libcxx}/lib/*; do
          ln -s $lib $out/lib/wasm32-wasi
        done
      '';
      firefoxWasmCc = firefoxSourcePkgs.writeShellScriptBin "olc-firefox-source-wasm-cc" ''
        unset NIX_LDFLAGS
        exec ${firefoxSourcePkgs.pkgsCross.wasi32.stdenv.cc}/bin/${firefoxSourcePkgs.pkgsCross.wasi32.stdenv.cc.targetPrefix}cc "$@"
      '';
      firefoxWasmCxx = firefoxSourcePkgs.writeShellScriptBin "olc-firefox-source-wasm-cxx" ''
        unset NIX_LDFLAGS
        exec ${firefoxSourcePkgs.pkgsCross.wasi32.stdenv.cc}/bin/${firefoxSourcePkgs.pkgsCross.wasi32.stdenv.cc.targetPrefix}c++ "$@"
      '';
      qemuPkgs = import nixpkgs {
        inherit system;
        overlays = [ qemuInputOverlay ];
      };
      overlayModule = {
        nixpkgs.overlays = [ firefoxFastOverlay qemuInputOverlay ];
      };
      olcModule = ./nix/ol-c.nix;
    in {
      overlays.default = firefoxFastOverlay;
      overlays.source = firefoxSourceOverlay;
      overlays.qemu-input = qemuInputOverlay;

      nixosConfigurations."ol-c" = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [ overlayModule olcModule ];
      };

      packages.${system} = {
        firefox-localhost = firefoxPkgs.firefox;
        firefox-localhost-source = firefoxSourcePkgs.firefox;
        novnc = basePkgs.novnc;
        pulseaudio = basePkgs.pulseaudio;
        qemu-olc = qemuPkgs.qemu_kvm;
        "ol-c-image" = self.nixosConfigurations."ol-c".config.system.build.images.qemu;
      };

      devShells.${system}.firefox-source = firefoxSourcePkgs.mkShell {
        inputsFrom = [ firefoxSourcePkgs.firefox-unwrapped ];
        packages = with firefoxSourcePkgs; [
          python3
          llvm
          clang
          llvmPackages.libclang
          pkg-config
          alsa-lib
        ];
        LIBCLANG_PATH = "${firefoxSourcePkgs.llvmPackages.libclang.lib}/lib";
        WASM_CC = "${firefoxWasmCc}/bin/olc-firefox-source-wasm-cc";
        WASM_CXX = "${firefoxWasmCxx}/bin/olc-firefox-source-wasm-cxx";
        OLC_FIREFOX_WASI_SYSROOT = "${firefoxWasiSysRoot}";
        MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE = "system";
        MOZ_NOSPAM = "1";
        shellHook = ''
          export CC="${firefoxSourcePkgs.clang}/bin/clang"
          export CXX="${firefoxSourcePkgs.clang}/bin/clang++"
          export HOST_CC="''${HOST_CC:-$CC}"
          export HOST_CXX="''${HOST_CXX:-$CXX}"
          export AS="$CC"
          export HOST_AS="$HOST_CC"
        '';
      };
    };
}
