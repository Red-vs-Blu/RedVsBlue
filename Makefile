all: update

update: migrate
	cp build/contracts/RedVsBlue.json ./site/src/contract/RedVsBlueABI.json

migrate: clean
	truffle migrate

clean:
	rm -rf build/contracts

deps:
	npm install
	$(MAKE) -C site deps

serve:
	$(MAKE) -C site serve

test:
	truffle test
