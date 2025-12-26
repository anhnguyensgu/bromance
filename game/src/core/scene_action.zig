pub const SceneAction = union(enum) {
    None,
    SwitchToLogin,
    SwitchToWorld,
    Quit,
};
