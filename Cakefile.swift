import Cakefile

dependencies = [
    .swift(4.2),
    .github("kishikawakatsumi/KeychainAccess" ~> 3.1),
    .github("mxcl/PromiseKit" ~> 6.7),
    .github("PromiseKit/Foundation" ~> 3.3),
    .github("PromiseKit/StoreKit" ~> 3.1),
    .github("ole/SortedArray" ~> 0.7),
]

platforms = [
    .macOS ~> 10.12,
    .iOS ~> 11.4,
]

