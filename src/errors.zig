pub const ConversionError = error{
    UnsupportedCpu,
    FpuSpecifiedForSoftFloatAbi,
    IncompatibleFpuForCpu,
    NoFpuOnCpu,
    FeatureOverflow,
    NotFreestanding,
};

pub const FlagTranslationError = error{
    MissingCpu,
    InvalidCpu,
    InvalidFloatAbi,
    InvalidFpu,
    MissingFpu,
};
