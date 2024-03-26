import ./basics

type SolidityError* = object of EthersError

{.push raises:[].}

template errors*(types) {.pragma.}
