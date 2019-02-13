import Cakefile

let keychainAccess = GitHubPackageSpecification(user: "mxcl", repo: "KeychainAccess", constraint: .ref(.branch("master")))

dependencies = [
    .cake(~>1.0),
    .github(keychainAccess),
    .github("mxcl/PromiseKit" ~> 6.7),
    .github("PromiseKit/Foundation" ~> 3.3),
    .github("PromiseKit/StoreKit" ~> 3.1),
    .github("ole/SortedArray" ~> 0.7),
    .github("mxcl/LegibleError" ~> 1),
]

platforms = [
    .macOS ~> 10.12,
    .iOS ~> 11.4,
]

