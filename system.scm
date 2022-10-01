
(define %my-nftables-ruleset
  (plain-file "nftables.conf"
  "
flush ruleset
table ip filter {
	chain INPUT {
		type filter hook input priority 0; policy accept;
	}

	chain FORWARD {
		type filter hook forward priority 0; policy accept;
		counter jump DOCKER-USER
		counter jump DOCKER-ISOLATION-STAGE-1
		oifname docker0 ct state established,related counter accept
		oifname docker0 counter jump DOCKER
		iifname docker0 oifname != docker0 counter accept
		iifname docker0 oifname docker0 counter accept
	}

	chain OUTPUT {
		type filter hook output priority 0; policy accept;
	}

	chain DOCKER {
	}

	chain DOCKER-ISOLATION-STAGE-1 {
		iifname docker0 oifname != docker0 counter jump DOCKER-ISOLATION-STAGE-2
		counter return
	}

	chain DOCKER-ISOLATION-STAGE-2 {
		oifname docker0 counter drop
		counter return
	}

	chain DOCKER-USER {
		counter return
	}
}
table ip nat {
	chain PREROUTING {
		type nat hook prerouting priority -100; policy accept;
		fib daddr type local counter jump DOCKER
	}

	chain INPUT {
		type nat hook input priority 100; policy accept;
	}

	chain POSTROUTING {
		type nat hook postrouting priority 100; policy accept;
		oifname != docker0 ip saddr 172.17.0.0/16 counter masquerade
	}

	chain OUTPUT {
		type nat hook output priority -100; policy accept;
		ip daddr != 127.0.0.0/8 fib daddr type local counter jump DOCKER
	}

	chain DOCKER {
		iifname docker0 counter return
	}
}
"))

(use-modules (gnu)
	     (nongnu packages linux)
	     (gnu packages xorg)
	     (gnu services docker)
	     (gnu services sound)
	     (gnu services virtualization))

(use-service-modules cups desktop networking ssh xorg nix)
(use-package-modules package-management)


(operating-system
 (kernel linux)
 (firmware (list linux-firmware sof-firmware))
  (locale "en_CA.utf8")
  (timezone "America/Toronto")
  (keyboard-layout (keyboard-layout "us"))
  (host-name "mycomputer")

  ;; The list of user accounts ('root' is implicit).
  (users (cons* (user-account
                  (name "twill")
                  (comment "Twill")
                  (group "users")
                  (home-directory "/home/twill")
                  (supplementary-groups '("wheel" "netdev" "audio" "video" "docker" "libvirt" "kvm")))
                %base-user-accounts))
  
  (packages (append (list
		     nix
		     (specification->package "emacs")
                     (specification->package "emacs-exwm")
                     (specification->package
                      "emacs-desktop-environment")
		     (specification->package "lxde")
                     (specification->package "nss-certs"))
                    %base-packages))

  ;; Below is the list of system services.  To search for available
  ;; services, run 'guix system search KEYWORD' in a terminal.
  (services 
   (cons* (service nftables-service-type
		   (nftables-configuration
		    (ruleset %my-nftables-ruleset)))
	  (service libvirt-service-type
		   (libvirt-configuration
		    (unix-sock-group "libvirt")
		    (tls-port "16555")))
	  (service virtlog-service-type
		   (virtlog-configuration
		    (max-clients 1000)))
          (bluetooth-service #:auto-enable? #t)
	  (service docker-service-type)
	  (service tor-service-type)
	  (service nix-service-type)	
	  (modify-services %desktop-services
			   (gdm-service-type config =>
					     (gdm-configuration
					      (default-user "twill")
					      (auto-login? #t))))))
  
  (bootloader (bootloader-configuration
                (bootloader grub-efi-bootloader)
                (targets (list "/boot/efi"))
                (keyboard-layout keyboard-layout)))
  (mapped-devices (list (mapped-device
                          (source (uuid
                                   "ad6b09fb-c969-4f2d-a580-62fd6f880718"))
                          (target "cryptroot")
                          (type luks-device-mapping))
                        (mapped-device
                          (source (uuid
                                   "690cc48c-ac27-4712-b2bc-9b11f49b9b76"))
                          (target "crypthome")
                          (type luks-device-mapping))))

  ;; The list of file systems that get "mounted".  The unique
  ;; file system identifiers there ("UUIDs") can be obtained
  ;; by running 'blkid' in a terminal.
  (file-systems (cons* (file-system
                         (mount-point "/boot/efi")
                         (device (uuid "2AA8-EC85"
                                       'fat32))
                         (type "vfat"))
                       (file-system
                         (mount-point "/")
                         (device "/dev/mapper/cryptroot")
                         (type "ext4")
                         (dependencies mapped-devices))
                       (file-system
                         (mount-point "/home")
                         (device "/dev/mapper/crypthome")
                         (type "ext4")
                         (dependencies mapped-devices)) %base-file-systems)))
