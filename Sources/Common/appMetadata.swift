public let stableWinMuxAppId: String = "com.qianningxu.oh-my-menubar"
#if DEBUG
    public let winMuxAppId: String = "com.qianningxu.oh-my-menubar.debug"
    public let winMuxAppName: String = "Oh-My-Menubar-Debug"
#else
    public let winMuxAppId: String = stableWinMuxAppId
    public let winMuxAppName: String = "Oh-My-Menubar"
#endif
