import { newMockEvent } from "matchstick-as"
import { ethereum, Address, BigInt, Bytes } from "@graphprotocol/graph-ts"
import {
  CoordinatorSet,
  KuriInitFailed,
  KuriInitialised,
  KuriSlotClaimed,
  MembershipRequested,
  OwnershipTransferRequested,
  OwnershipTransferred,
  RaffleWinnerSelected,
  RoleAdminChanged,
  RoleGranted,
  RoleRevoked,
  UserAccepted,
  UserDeposited,
  UserFlagged,
  UserRejected,
  VRFIntegrationDone
} from "../generated/KuriCore/KuriCore"

export function createCoordinatorSetEvent(
  vrfCoordinator: Address
): CoordinatorSet {
  let coordinatorSetEvent = changetype<CoordinatorSet>(newMockEvent())

  coordinatorSetEvent.parameters = new Array()

  coordinatorSetEvent.parameters.push(
    new ethereum.EventParam(
      "vrfCoordinator",
      ethereum.Value.fromAddress(vrfCoordinator)
    )
  )

  return coordinatorSetEvent
}

export function createKuriInitFailedEvent(
  creator: Address,
  kuriAmount: BigInt,
  totalParticipantsCount: i32,
  state: i32
): KuriInitFailed {
  let kuriInitFailedEvent = changetype<KuriInitFailed>(newMockEvent())

  kuriInitFailedEvent.parameters = new Array()

  kuriInitFailedEvent.parameters.push(
    new ethereum.EventParam("creator", ethereum.Value.fromAddress(creator))
  )
  kuriInitFailedEvent.parameters.push(
    new ethereum.EventParam(
      "kuriAmount",
      ethereum.Value.fromUnsignedBigInt(kuriAmount)
    )
  )
  kuriInitFailedEvent.parameters.push(
    new ethereum.EventParam(
      "totalParticipantsCount",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(totalParticipantsCount))
    )
  )
  kuriInitFailedEvent.parameters.push(
    new ethereum.EventParam(
      "state",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(state))
    )
  )

  return kuriInitFailedEvent
}

export function createKuriInitialisedEvent(
  _kuriData: ethereum.Tuple
): KuriInitialised {
  let kuriInitialisedEvent = changetype<KuriInitialised>(newMockEvent())

  kuriInitialisedEvent.parameters = new Array()

  kuriInitialisedEvent.parameters.push(
    new ethereum.EventParam("_kuriData", ethereum.Value.fromTuple(_kuriData))
  )

  return kuriInitialisedEvent
}

export function createKuriSlotClaimedEvent(
  user: Address,
  timestamp: BigInt,
  kuriAmount: BigInt,
  intervalIndex: i32
): KuriSlotClaimed {
  let kuriSlotClaimedEvent = changetype<KuriSlotClaimed>(newMockEvent())

  kuriSlotClaimedEvent.parameters = new Array()

  kuriSlotClaimedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  kuriSlotClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "timestamp",
      ethereum.Value.fromUnsignedBigInt(timestamp)
    )
  )
  kuriSlotClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "kuriAmount",
      ethereum.Value.fromUnsignedBigInt(kuriAmount)
    )
  )
  kuriSlotClaimedEvent.parameters.push(
    new ethereum.EventParam(
      "intervalIndex",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(intervalIndex))
    )
  )

  return kuriSlotClaimedEvent
}

export function createMembershipRequestedEvent(
  user: Address,
  timestamp: BigInt
): MembershipRequested {
  let membershipRequestedEvent = changetype<MembershipRequested>(newMockEvent())

  membershipRequestedEvent.parameters = new Array()

  membershipRequestedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  membershipRequestedEvent.parameters.push(
    new ethereum.EventParam(
      "timestamp",
      ethereum.Value.fromUnsignedBigInt(timestamp)
    )
  )

  return membershipRequestedEvent
}

export function createOwnershipTransferRequestedEvent(
  from: Address,
  to: Address
): OwnershipTransferRequested {
  let ownershipTransferRequestedEvent =
    changetype<OwnershipTransferRequested>(newMockEvent())

  ownershipTransferRequestedEvent.parameters = new Array()

  ownershipTransferRequestedEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  ownershipTransferRequestedEvent.parameters.push(
    new ethereum.EventParam("to", ethereum.Value.fromAddress(to))
  )

  return ownershipTransferRequestedEvent
}

export function createOwnershipTransferredEvent(
  from: Address,
  to: Address
): OwnershipTransferred {
  let ownershipTransferredEvent =
    changetype<OwnershipTransferred>(newMockEvent())

  ownershipTransferredEvent.parameters = new Array()

  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam("from", ethereum.Value.fromAddress(from))
  )
  ownershipTransferredEvent.parameters.push(
    new ethereum.EventParam("to", ethereum.Value.fromAddress(to))
  )

  return ownershipTransferredEvent
}

export function createRaffleWinnerSelectedEvent(
  intervalIndex: i32,
  winnerIndex: i32,
  winnerAddress: Address,
  winnerTimestamp: BigInt,
  requestId: BigInt
): RaffleWinnerSelected {
  let raffleWinnerSelectedEvent =
    changetype<RaffleWinnerSelected>(newMockEvent())

  raffleWinnerSelectedEvent.parameters = new Array()

  raffleWinnerSelectedEvent.parameters.push(
    new ethereum.EventParam(
      "intervalIndex",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(intervalIndex))
    )
  )
  raffleWinnerSelectedEvent.parameters.push(
    new ethereum.EventParam(
      "winnerIndex",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(winnerIndex))
    )
  )
  raffleWinnerSelectedEvent.parameters.push(
    new ethereum.EventParam(
      "winnerAddress",
      ethereum.Value.fromAddress(winnerAddress)
    )
  )
  raffleWinnerSelectedEvent.parameters.push(
    new ethereum.EventParam(
      "winnerTimestamp",
      ethereum.Value.fromUnsignedBigInt(winnerTimestamp)
    )
  )
  raffleWinnerSelectedEvent.parameters.push(
    new ethereum.EventParam(
      "requestId",
      ethereum.Value.fromUnsignedBigInt(requestId)
    )
  )

  return raffleWinnerSelectedEvent
}

export function createRoleAdminChangedEvent(
  role: Bytes,
  previousAdminRole: Bytes,
  newAdminRole: Bytes
): RoleAdminChanged {
  let roleAdminChangedEvent = changetype<RoleAdminChanged>(newMockEvent())

  roleAdminChangedEvent.parameters = new Array()

  roleAdminChangedEvent.parameters.push(
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role))
  )
  roleAdminChangedEvent.parameters.push(
    new ethereum.EventParam(
      "previousAdminRole",
      ethereum.Value.fromFixedBytes(previousAdminRole)
    )
  )
  roleAdminChangedEvent.parameters.push(
    new ethereum.EventParam(
      "newAdminRole",
      ethereum.Value.fromFixedBytes(newAdminRole)
    )
  )

  return roleAdminChangedEvent
}

export function createRoleGrantedEvent(
  role: Bytes,
  account: Address,
  sender: Address
): RoleGranted {
  let roleGrantedEvent = changetype<RoleGranted>(newMockEvent())

  roleGrantedEvent.parameters = new Array()

  roleGrantedEvent.parameters.push(
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role))
  )
  roleGrantedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )
  roleGrantedEvent.parameters.push(
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender))
  )

  return roleGrantedEvent
}

export function createRoleRevokedEvent(
  role: Bytes,
  account: Address,
  sender: Address
): RoleRevoked {
  let roleRevokedEvent = changetype<RoleRevoked>(newMockEvent())

  roleRevokedEvent.parameters = new Array()

  roleRevokedEvent.parameters.push(
    new ethereum.EventParam("role", ethereum.Value.fromFixedBytes(role))
  )
  roleRevokedEvent.parameters.push(
    new ethereum.EventParam("account", ethereum.Value.fromAddress(account))
  )
  roleRevokedEvent.parameters.push(
    new ethereum.EventParam("sender", ethereum.Value.fromAddress(sender))
  )

  return roleRevokedEvent
}

export function createUserAcceptedEvent(
  user: Address,
  caller: Address,
  _totalActiveParticipantsCount: i32
): UserAccepted {
  let userAcceptedEvent = changetype<UserAccepted>(newMockEvent())

  userAcceptedEvent.parameters = new Array()

  userAcceptedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  userAcceptedEvent.parameters.push(
    new ethereum.EventParam("caller", ethereum.Value.fromAddress(caller))
  )
  userAcceptedEvent.parameters.push(
    new ethereum.EventParam(
      "_totalActiveParticipantsCount",
      ethereum.Value.fromUnsignedBigInt(
        BigInt.fromI32(_totalActiveParticipantsCount)
      )
    )
  )

  return userAcceptedEvent
}

export function createUserDepositedEvent(
  user: Address,
  userIndex: BigInt,
  intervalIndex: BigInt,
  amountDeposited: BigInt,
  depositTimestamp: BigInt
): UserDeposited {
  let userDepositedEvent = changetype<UserDeposited>(newMockEvent())

  userDepositedEvent.parameters = new Array()

  userDepositedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  userDepositedEvent.parameters.push(
    new ethereum.EventParam(
      "userIndex",
      ethereum.Value.fromUnsignedBigInt(userIndex)
    )
  )
  userDepositedEvent.parameters.push(
    new ethereum.EventParam(
      "intervalIndex",
      ethereum.Value.fromUnsignedBigInt(intervalIndex)
    )
  )
  userDepositedEvent.parameters.push(
    new ethereum.EventParam(
      "amountDeposited",
      ethereum.Value.fromUnsignedBigInt(amountDeposited)
    )
  )
  userDepositedEvent.parameters.push(
    new ethereum.EventParam(
      "depositTimestamp",
      ethereum.Value.fromUnsignedBigInt(depositTimestamp)
    )
  )

  return userDepositedEvent
}

export function createUserFlaggedEvent(
  user: Address,
  intervalIndex: i32
): UserFlagged {
  let userFlaggedEvent = changetype<UserFlagged>(newMockEvent())

  userFlaggedEvent.parameters = new Array()

  userFlaggedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  userFlaggedEvent.parameters.push(
    new ethereum.EventParam(
      "intervalIndex",
      ethereum.Value.fromUnsignedBigInt(BigInt.fromI32(intervalIndex))
    )
  )

  return userFlaggedEvent
}

export function createUserRejectedEvent(
  user: Address,
  caller: Address
): UserRejected {
  let userRejectedEvent = changetype<UserRejected>(newMockEvent())

  userRejectedEvent.parameters = new Array()

  userRejectedEvent.parameters.push(
    new ethereum.EventParam("user", ethereum.Value.fromAddress(user))
  )
  userRejectedEvent.parameters.push(
    new ethereum.EventParam("caller", ethereum.Value.fromAddress(caller))
  )

  return userRejectedEvent
}

export function createVRFIntegrationDoneEvent(
  caller: Address,
  subscriptionId: BigInt,
  consumerCount: BigInt,
  contractAddress: Address,
  timestamp: BigInt
): VRFIntegrationDone {
  let vrfIntegrationDoneEvent = changetype<VRFIntegrationDone>(newMockEvent())

  vrfIntegrationDoneEvent.parameters = new Array()

  vrfIntegrationDoneEvent.parameters.push(
    new ethereum.EventParam("caller", ethereum.Value.fromAddress(caller))
  )
  vrfIntegrationDoneEvent.parameters.push(
    new ethereum.EventParam(
      "subscriptionId",
      ethereum.Value.fromUnsignedBigInt(subscriptionId)
    )
  )
  vrfIntegrationDoneEvent.parameters.push(
    new ethereum.EventParam(
      "consumerCount",
      ethereum.Value.fromUnsignedBigInt(consumerCount)
    )
  )
  vrfIntegrationDoneEvent.parameters.push(
    new ethereum.EventParam(
      "contractAddress",
      ethereum.Value.fromAddress(contractAddress)
    )
  )
  vrfIntegrationDoneEvent.parameters.push(
    new ethereum.EventParam(
      "timestamp",
      ethereum.Value.fromUnsignedBigInt(timestamp)
    )
  )

  return vrfIntegrationDoneEvent
}
