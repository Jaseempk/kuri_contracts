import {
  CoordinatorSet as CoordinatorSetEvent,
  KuriInitFailed as KuriInitFailedEvent,
  KuriInitialised as KuriInitialisedEvent,
  KuriSlotClaimed as KuriSlotClaimedEvent,
  OwnershipTransferRequested as OwnershipTransferRequestedEvent,
  OwnershipTransferred as OwnershipTransferredEvent,
  RaffleWinnerSelected as RaffleWinnerSelectedEvent,
  RoleAdminChanged as RoleAdminChangedEvent,
  RoleGranted as RoleGrantedEvent,
  RoleRevoked as RoleRevokedEvent,
  UserDeposited as UserDepositedEvent,
} from "../generated/templates/KuriCore/KuriCore";
import {
  CoordinatorSet,
  KuriInitFailed,
  KuriInitialised,
  KuriSlotClaimed,
  OwnershipTransferRequested,
  OwnershipTransferred,
  RaffleWinnerSelected,
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
  UserDeposited,
} from "../generated/schema";

export function handleCoordinatorSet(event: CoordinatorSetEvent): void {
  let entity = new CoordinatorSet(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.vrfCoordinator = event.params.vrfCoordinator;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleKuriInitFailed(event: KuriInitFailedEvent): void {
  let entity = new KuriInitFailed(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.creator = event.params.creator;
  entity.kuriAmount = event.params.kuriAmount;
  entity.totalParticipantsCount = event.params.totalParticipantsCount;
  entity.state = event.params.state;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleKuriInitialised(event: KuriInitialisedEvent): void {
  let entity = new KuriInitialised(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity._kuriData_creator = event.params._kuriData.creator;
  entity._kuriData_kuriAmount = event.params._kuriData.kuriAmount;
  entity._kuriData_totalParticipantsCount =
    event.params._kuriData.totalParticipantsCount;
  entity._kuriData_totalActiveParticipantsCount =
    event.params._kuriData.totalActiveParticipantsCount;
  entity._kuriData_intervalDuration = event.params._kuriData.intervalDuration;
  entity._kuriData_nexRaffleTime = event.params._kuriData.nexRaffleTime;
  entity._kuriData_nextIntervalDepositTime =
    event.params._kuriData.nextIntervalDepositTime;
  entity._kuriData_launchPeriod = event.params._kuriData.launchPeriod;
  entity._kuriData_startTime = event.params._kuriData.startTime;
  entity._kuriData_endTime = event.params._kuriData.endTime;
  entity._kuriData_intervalType = event.params._kuriData.intervalType;
  entity._kuriData_state = event.params._kuriData.state;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleKuriSlotClaimed(event: KuriSlotClaimedEvent): void {
  let entity = new KuriSlotClaimed(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = event.params.user;
  entity.timestamp = event.params.timestamp;
  entity.kuriAmount = event.params.kuriAmount;
  entity.intervalIndex = event.params.intervalIndex;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleOwnershipTransferRequested(
  event: OwnershipTransferRequestedEvent
): void {
  let entity = new OwnershipTransferRequested(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.from = event.params.from;
  entity.to = event.params.to;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleOwnershipTransferred(
  event: OwnershipTransferredEvent
): void {
  let entity = new OwnershipTransferred(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.from = event.params.from;
  entity.to = event.params.to;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleRaffleWinnerSelected(
  event: RaffleWinnerSelectedEvent
): void {
  let entity = new RaffleWinnerSelected(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.intervalIndex = event.params.intervalIndex;
  entity.winnerIndex = event.params.winnerIndex;
  entity.winnerAddress = event.params.winnerAddress;
  entity.winnerTimestamp = event.params.winnerTimestamp;
  entity.requestId = event.params.requestId;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleRoleAdminChanged(event: RoleAdminChangedEvent): void {
  let entity = new RoleAdminChanged(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.role = event.params.role;
  entity.previousAdminRole = event.params.previousAdminRole;
  entity.newAdminRole = event.params.newAdminRole;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleRoleGranted(event: RoleGrantedEvent): void {
  let entity = new RoleGranted(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.role = event.params.role;
  entity.account = event.params.account;
  entity.sender = event.params.sender;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleRoleRevoked(event: RoleRevokedEvent): void {
  let entity = new RoleRevoked(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.role = event.params.role;
  entity.account = event.params.account;
  entity.sender = event.params.sender;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}

export function handleUserDeposited(event: UserDepositedEvent): void {
  let entity = new UserDeposited(
    event.transaction.hash.concatI32(event.logIndex.toI32())
  );
  entity.user = event.params.user;
  entity.userIndex = event.params.userIndex;
  entity.intervalIndex = event.params.intervalIndex;
  entity.amountDeposited = event.params.amountDeposited;
  entity.depositTimestamp = event.params.depositTimestamp;

  entity.blockNumber = event.block.number;
  entity.blockTimestamp = event.block.timestamp;
  entity.transactionHash = event.transaction.hash;

  entity.save();
}
