all: update

NETWORK_NAME := ganache

update: migrate
	cp build/contracts/RedVsBlue.json ../Red-vs-Blu.github.io/src/contract/RedVsBlueABI.json

migrate: clean
	truffle migrate --reset --network $(NETWORK_NAME)

clean:
	rm -rf build/contracts

test:
	truffle test
