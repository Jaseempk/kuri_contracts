import {
  assert,
  describe,
  test,
  clearStore,
  beforeAll,
  afterAll
} from "matchstick-as/assembly/index"
import { Address, BigInt } from "@graphprotocol/graph-ts"
import { KuriMarketDeployed } from "../generated/schema"
import { KuriMarketDeployed as KuriMarketDeployedEvent } from "../generated/KuriCoreFactory/KuriCoreFactory"
import { handleKuriMarketDeployed } from "../src/kuri-core-factory"
import { createKuriMarketDeployedEvent } from "./kuri-core-factory-utils"

// Tests structure (matchstick-as >=0.5.0)
// https://thegraph.com/docs/en/developer/matchstick/#tests-structure-0-5-0

describe("Describe entity assertions", () => {
  beforeAll(() => {
    let caller = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let marketAddress = Address.fromString(
      "0x0000000000000000000000000000000000000001"
    )
    let intervalType = 123
    let timestamp = BigInt.fromI32(234)
    let newKuriMarketDeployedEvent = createKuriMarketDeployedEvent(
      caller,
      marketAddress,
      intervalType,
      timestamp
    )
    handleKuriMarketDeployed(newKuriMarketDeployedEvent)
  })

  afterAll(() => {
    clearStore()
  })

  // For more test scenarios, see:
  // https://thegraph.com/docs/en/developer/matchstick/#write-a-unit-test

  test("KuriMarketDeployed created and stored", () => {
    assert.entityCount("KuriMarketDeployed", 1)

    // 0xa16081f360e3847006db660bae1c6d1b2e17ec2a is the default address used in newMockEvent() function
    assert.fieldEquals(
      "KuriMarketDeployed",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "caller",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "KuriMarketDeployed",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "marketAddress",
      "0x0000000000000000000000000000000000000001"
    )
    assert.fieldEquals(
      "KuriMarketDeployed",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "intervalType",
      "123"
    )
    assert.fieldEquals(
      "KuriMarketDeployed",
      "0xa16081f360e3847006db660bae1c6d1b2e17ec2a-1",
      "timestamp",
      "234"
    )

    // More assert options:
    // https://thegraph.com/docs/en/developer/matchstick/#asserts
  })
})
