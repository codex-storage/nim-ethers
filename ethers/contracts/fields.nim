import std/macros

macro fieldValues*(obj: object): auto =
  result = newNimNode(nnkTupleConstr)
  let typ = getTypeImpl(obj)
  let fields = typ[2]
  for field in fields:
    let name = field[0]
    result.add newDotExpr(obj, name)

template fieldTypes*(T: type): type tuple =
  typeof fieldValues(T.default)
