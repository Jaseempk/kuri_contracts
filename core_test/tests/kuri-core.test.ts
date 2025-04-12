import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import { CoordinatorSet } from "../generated/schema"
import { CoordinatorSet as CoordinatorSetEvent } from "../generated/KuriCore/KuriCore"
import { handleCoordinatorSet } from "../src/kuri-core"
import { createCoordinatorSetEvent } from "./kuri-core-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let vrfCoordinator = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let newCoordinatorSetEvent = createCoordinatorSetEvent(vrfCoordinator)
    handleCoordinatorSet(newCoordinatorSetEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("CoordinatorSet created and stored", () => {
    assert.entityCount("CoordinatorSet", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "CoordinatorSet",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "vrfCoordinator",
      "0x0000000000000000000000000000000000000001"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
