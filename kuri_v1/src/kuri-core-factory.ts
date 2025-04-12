import { KuriMarketDeployed as KuriMarketDeployedEvent } from "../generated/KuriCoreFactory/KuriCoreFactory";
import { KuriMarketDeployed } from "../generated/schema";
import { KuriCore } from "../generated/templates";

export function handleKuriMarketDeployed(event: KuriMarketDeployedEvent): void {
  let entity = new KuriMarketDeployed(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.caller = event.params.caller;
  entity.marketAddress = event.params.marketAddress;
  entity.intervalType = event.params.intervalType;
  entity.timestamp = event.params.timestamp;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
  KuriCore.create(event.params.marketAddress);
}
