import std/math
import std/options
import std/strformat
import std/strutils
import std/unittest
import pkg/stew/byteutils
import pkg/stint
import pkg/ethers/providers/jsonrpc/json as utilsjson
import pkg/questionable
import pkg/questionable/results


func flatten(s: string): string =
  s.replace(" ")
    .replace("\n")

suite "json serialization - serialize":

  test "serializes UInt256 to non-hex string representation":
    check (% 100000.u256) == newJString("100000")

  test "serializes sequence to an array":
    let json = % @[1, 2, 3]
    let expected = "[1,2,3]"
    check $json == expected

  test "serializes Option[T] when has a value":
    let obj = %(some 1)
    let expected = "1"
    check $obj == expected

  test "serializes Option[T] when doesn't have a value":
    let obj = %(none int)
    let expected = "null"
    check $obj == expected

  test "serializes uints int.high or smaller":
    let largeUInt: uint = uint(int.high)
    check %largeUInt == newJInt(BiggestInt(largeUInt))

  test "serializes large uints":
    let largeUInt: uint = uint(int.high) + 1'u
    check %largeUInt == newJString($largeUInt)

  test "serializes Inf float":
    check %Inf == newJString("inf")

  test "serializes -Inf float":
    check %(-Inf) == newJString("-inf")

  test "can construct json objects with %*":
    type MyObj = object
      mystring {.serialize.}: string
      myint {.serialize.}: int
      myoption {.serialize.}: ?bool

    let myobj = MyObj(mystring: "abc", myint: 123, myoption: some true)
    let mystuint = 100000.u256

    let json = %*{
      "myobj": myobj,
      "mystuint": mystuint
    }

    let expected = """{
                        "myobj": {
                          "mystring": "abc",
                          "myint": 123,
                          "myoption": true
                        },
                        "mystuint": "100000"
                      }""".flatten

    check $json == expected

  test "only serializes marked fields":
    type MyObj = object
      mystring {.serialize.}: string
      myint {.serialize.}: int
      mybool: bool

    let obj = % MyObj(mystring: "abc", myint: 1, mybool: true)

    let expected = """{
                        "mystring": "abc",
                        "myint": 1
                      }""".flatten

    check $obj == expected

  test "serializes ref objects":
    type MyRef = ref object
      mystring {.serialize.}: string
      myint {.serialize.}: int

    let obj = % MyRef(mystring: "abc", myint: 1)

    let expected = """{
                        "mystring": "abc",
                        "myint": 1
                      }""".flatten

    check $obj == expected

suite "json serialization - deserialize":

  test "deserializes NaN float":
    check %NaN == newJString("nan")

  test "deserialize enum":
    type MyEnum = enum
      First,
      Second
    let json = newJString("Second")
    check !MyEnum.fromJson(json) == Second

  test "deserializes UInt256 from non-hex string representation":
    let json = newJString("100000")
    check !UInt256.fromJson(json) == 100000.u256

  test "deserializes Option[T] when has a value":
    let json = newJInt(1)
    check (!fromJson(?int, json) == some 1)

  test "deserializes Option[T] when doesn't have a value":
    let json = newJNull()
    check !fromJson(?int, json) == none int

  test "deserializes float":
    let json = newJFloat(1.234)
    check !float.fromJson(json) == 1.234

  test "deserializes Inf float":
    let json = newJString("inf")
    check !float.fromJson(json) == Inf

  test "deserializes -Inf float":
    let json = newJString("-inf")
    check !float.fromJson(json) == -Inf

  test "deserializes NaN float":
    let json = newJString("nan")
    check (!float.fromJson(json)).isNaN

  test "deserializes array to sequence":
    let expected = @[1, 2, 3]
    let json = !"[1,2,3]".parseJson
    check !seq[int].fromJson(json) == expected

  test "deserializes uints int.high or smaller":
    let largeUInt: uint = uint(int.high)
    let json = newJInt(BiggestInt(largeUInt))
    check !uint.fromJson(json) == largeUInt

  test "deserializes large uints":
    let largeUInt: uint = uint(int.high) + 1'u
    let json = newJString($BiggestUInt(largeUInt))
    check !uint.fromJson(json) == largeUInt

  test "can deserialize json objects":
    type MyObj = object
      mystring: string
      myint: int
      myoption: ?bool

    let expected = MyObj(mystring: "abc", myint: 123, myoption: some true)

    let json = !parseJson("""{
                              "mystring": "abc",
                              "myint": 123,
                              "myoption": true
                            }""")
    check !MyObj.fromJson(json) == expected

  test "ignores serialize pragma when deserializing":
    type MyObj = object
      mystring {.serialize.}: string
      mybool: bool

    let expected = MyObj(mystring: "abc", mybool: true)

    let json = !parseJson("""{
                              "mystring": "abc",
                              "mybool": true
                            }""")

    check !MyObj.fromJson(json) == expected

  test "deserializes objects with extra fields":
    type MyObj = object
      mystring: string
      mybool: bool

    let expected = MyObj(mystring: "abc", mybool: true)

    let json = !"""{
                    "mystring": "abc",
                    "mybool": true,
                    "extra": "extra"
                  }""".parseJson
    check !MyObj.fromJson(json) == expected

  test "deserializes objects with less fields":
    type MyObj = object
      mystring: string
      mybool: bool

    let expected = MyObj(mystring: "abc", mybool: false)

    let json = !"""{
                    "mystring": "abc"
                  }""".parseJson
    check !MyObj.fromJson(json) == expected

  test "deserializes ref objects":
    type MyRef = ref object
      mystring: string
      myint: int

    let expected = MyRef(mystring: "abc", myint: 1)

    let json = !"""{
                    "mystring": "abc",
                    "myint": 1
                  }""".parseJson

    let deserialized = !MyRef.fromJson(json)
    check deserialized.mystring == expected.mystring
    check deserialized.myint == expected.myint

suite "json serialization pragmas":

  test "fails to compile when object marked with 'serialize' specifies options":
    type
      MyObj {.serialize(key="test", ignore=true).} = object

    check not compiles(%MyObj())

  test "compiles when object marked with 'serialize' only":
    type
      MyObj {.serialize.} = object

    check compiles(%MyObj())

  test "fails to compile when field marked with 'deserialize' specifies mode":
    type
      MyObj = object
       field {.deserialize(mode=OptIn).}: bool

    check not compiles(MyObj.fromJson("""{"field":true}"""))

  test "compiles when object marked with 'deserialize' specifies mode":
    type
      MyObj {.deserialize(mode=OptIn).} = object
       field: bool

    check compiles(MyObj.fromJson("""{"field":true}"""))

  test "fails to compile when object marked with 'deserialize' specifies key":
    type
      MyObj {.deserialize("test").} = object
       field: bool

    check not compiles(MyObj.fromJson("""{"field":true}"""))

  test "compiles when field marked with 'deserialize' specifies key":
    type
      MyObj = object
       field {.deserialize("test").}: bool

    check compiles(MyObj.fromJson("""{"field":true}"""))

  test "compiles when field marked with empty 'deserialize'":
    type
      MyObj = object
       field {.deserialize.}: bool

    check compiles(MyObj.fromJson("""{"field":true}"""))

  test "compiles when field marked with 'serialize'":
    type
      MyObj = object
        field {.serialize.}: bool

    check compiles(%MyObj())

  test "serializes field with key when specified":
    type MyObj = object
      field {.serialize("test").}: bool

    let obj = MyObj(field: true)
    check obj.toJson == """{"test":true}"""

  test "does not serialize ignored field":
    type MyObj = object
      field1 {.serialize.}: bool
      field2 {.serialize(ignore=true).}: bool

    let obj = MyObj(field1: true, field2: true)
    check obj.toJson == """{"field1":true}"""

  test "serialize on object definition serializes all fields":
    type MyObj {.serialize.} = object
      field1: bool
      field2: bool

    let obj = MyObj(field1: true, field2: true)
    check obj.toJson == """{"field1":true,"field2":true}"""

  test "ignores field when object has serialize":
    type MyObj {.serialize.} = object
      field1 {.serialize(ignore=true).}: bool
      field2: bool

    let obj = MyObj(field1: true, field2: true)
    check obj.toJson == """{"field2":true}"""

  test "serializes field with key when object has serialize":
    type MyObj {.serialize.} = object
      field1 {.serialize("test").}: bool
      field2: bool

    let obj = MyObj(field1: true, field2: true)
    check obj.toJson == """{"test":true,"field2":true}"""

  test "deserializes matching object and json fields when mode is Strict":
    type MyObj {.deserialize(mode=Strict).} = object
      field1: bool
      field2: bool

    let val = !MyObj.fromJson("""{"field1":true,"field2":true}""")
    check val == MyObj(field1: true, field2: true)

  test "fails to deserialize with missing json field when mode is Strict":
    type MyObj {.deserialize(mode=Strict).} = object
      field1: bool
      field2: bool

    let r = MyObj.fromJson("""{"field2":true}""")
    check r.isFailure
    check r.error of SerdeError
    check r.error.msg == "object field missing in json: field1"

  test "fails to deserialize with missing object field when mode is Strict":
    type MyObj {.deserialize(mode=Strict).} = object
      field2: bool

    let r = MyObj.fromJson("""{"field1":true,"field2":true}""")
    check r.isFailure
    check r.error of SerdeError
    check r.error.msg == "json field(s) missing in object: {\"field1\"}"

  test "deserializes only fields marked as deserialize when mode is OptIn":
    type MyObj {.deserialize(mode=OptIn).} = object
      field1: int
      field2 {.deserialize.}: bool

    let val = !MyObj.fromJson("""{"field1":true,"field2":true}""")
    check val == MyObj(field1: 0, field2: true)

  test "can deserialize object in default mode when not marked with deserialize":
    type MyObj = object
      field1: bool
      field2: bool

    let val = !MyObj.fromJson("""{"field1":true,"field3":true}""")
    check val == MyObj(field1: true, field2: false)

  test "deserializes object field with marked json key":
    type MyObj = object
      field1 {.deserialize("test").}: bool
      field2: bool

    let val = !MyObj.fromJson("""{"test":true,"field2":true}""")
    check val == MyObj(field1: true, field2: true)

  test "deserialization key can be set using serialize key":
    type MyObj = object
      field1 {.serialize("test").}: bool
      field2: bool

    let val = !MyObj.fromJson("""{"test":true,"field2":true}""")
    check val == MyObj(field1: true, field2: true)

  test "deserialization key takes priority over serialize key":
    type MyObj = object
      field1 {.serialize("test"), deserialize("test1").}: bool
      field2: bool

    let val = !MyObj.fromJson("""{"test":false,"test1":true,"field2":true}""")
    check val == MyObj(field1: true, field2: true)

  test "fails to deserialize object field with wrong type":
    type MyObj = object
      field1: int
      field2: bool

    let r = MyObj.fromJson("""{"field1":true,"field2":true}""")
    check r.isFailure
    check r.error of UnexpectedKindError
    check r.error.msg == "deserialization to int failed: expected {JInt} but got JBool"
