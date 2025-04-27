-include .env

.PHONY: all test clean deploy fund help install snapshot format anvil 

DEFAULT_KEY := 

help:
	@echo "Usage:"
	@echo "  make deploy [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""
	@echo ""
	@echo "  make fund [ARGS=...]\n    example: make deploy ARGS=\"--network sepolia\""

all: clean remove install update build

# Clean the repo
clean  :; forge clean

# Remove modules
remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

anvil :; anvil -m 'test test test test test test test test test test test junk' --steps-tracing --block-time 1

NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast

ifeq ($(findstring --network ethereum,$(ARGS)),--network ethereum)
	NETWORK_ARGS := --rpc-url $(ALCHEMY_RPC_URL) --private-key $(METAMASK_PRIVATE_KEY) --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY) -vvvv
endif

createSubscription:
	@forge script script/Interactions.s.sol:CreateSubscription $(NETWORK_ARGS)

addConsumer:
	@forge script script/Interactions.s.sol:AddConsumer $(NETWORK_ARGS)

fundSubscription:
	@forge script script/Interactions.s.sol:FundSubscription $(NETWORK_ARGS)

deploy:
	@forge script script/DeployKuriCore.s.sol:DeployKuriCore $(NETWORK_ARGS)

verify:
	@forge verify-contract --chain-id 84532 --watch --constructor-args `cast abi-encode "constructor(uint64,uint16,address,uint8)" "$(KURIAMOUNT)" "$(PARTICIPANT_COUNT)" "$(INITIALISER)" "$(INTERVAL_TYPE)"` --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0x7c213c3B7f356F0D73023a75B3b41bb4423C8fF0 src/KuriCore.sol:KuriCore
#@forge verify-contract --chain-id 84532 --watch --etherscan-api-key $(ETHERSCAN_API_KEY) --compiler-version 0.8.27 0x3E7497056B541546Ea677EFfd3B9A4fDd4456e7C src/KuriCoreFactory.sol:KuriCoreFactory


