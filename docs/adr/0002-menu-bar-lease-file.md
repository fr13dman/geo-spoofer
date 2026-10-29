# Menu-bar app and an on-disk lease

The expiration can arrive while the main window is closed, so closing the window leaves a menu-bar app running and that process sends Clear. The lease is stored on disk because a full quit, or a relaunch, still has to know whether Clear is due. A separate background helper is not used. The next launch reads the lease and sends Clear when the expiration has passed.
