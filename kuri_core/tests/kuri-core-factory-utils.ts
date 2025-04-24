import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt } from "@graphprotocol/graph-ts"
import { KuriMarketDeployed } from "../generated/KuriCoreFactory/KuriCoreFactory"

export function createKuriMarketDeployedEvent(
  caller: Address,
  marketAddress: Address,
  intervalType: i32,
  timestamp: BigInt
): KuriMarketDeployed {
  let kuriMarketDeployedEvent = changetype<KuriMarketDeployed>(newMockEvent())

  kuriMarketDeployedEvent.parameters = new Array()

  kuriMarketDeployedEvent.parameters.push(
    new ethereum.EventParam("caller", ethereum.Value.fromAddress(caller))
  )
  kuriMarketDeployedEvent.parameters.push(
    new ethereum.EventParam(
      "marketAddress",
      ethereum.Value.fromAddress(marketAddress)
    )
  )
  kuriMarketDeployedEvent.parameters.push(
    new ethereum.EventParam(
      "intervalType",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(intervalType))
    )
  )
  kuriMarketDeployedEvent.parameters.push(
    new ethereum.EventParam(
      "timestamp",
      ethereum.Value.fromUnsignedBigInt(timestamp)
    )
  )

  return kuriMarketDeployedEvent
}
