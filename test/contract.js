const RedVsBlue = artifacts.require("RedVsBlue");

contract("RedVsBlue", (accounts) => {
    ////////////////////////////////////////////////////////////////////////////

    let contract = undefined;
    let deployed_block = -1;

    ////////////////////////////////////////////////////////////////////////////

    const VOTE_RED = 0;
    const VOTE_BLUE = 1;

    ////////////////////////////////////////////////////////////////////////////

    const owner_acct = accounts[0];
    const dummy_acct = accounts[9];

    ////////////////////////////////////////////////////////////////////////////

    before(async () => {
        contract = await RedVsBlue.deployed();
        deployed_block = await web3.eth.getBlock("latest");
    });

    beforeEach(async () => {
        // Nothing to do.
    });

    const finishCurrentRound = async (str) => {
        if (str !== undefined) { console.log(str); }

        for (let gid = await contract.GetCurrentGame(); gid.eq(await contract.GetCurrentGame());) {
            let result = await contract.BuyCredits({from: dummy_acct, value: from_credits("1")});
            assert.notEqual(result.tx, undefined);
        }
    };

    const to_credits = (n) => { return web3.utils.fromWei(n, "milli"); }
    const from_credits = (n) => { return web3.utils.toWei(n, "milli"); }
    const apply_fee = (n) => { return (n * 1.0) * (1.0); }

    ////////////////////////////////////////////////////////////////////////////

    //
    //  Basic contract tests.
    //

    it("has the right owner (accounts[0])", async () => {
        assert.equal(await contract.owner_address(), accounts[0], "accounts[0] should own this contract");
    });

    it("has a valid game id", async () => {
        const gid = await contract.GetCurrentGame();
        assert.equal(gid, parseInt(deployed_block.number / 128), "check game id");
    });

    it("has no game totals", async () => {
        let err, result = await contract.GetGameTotals(0);
        assert.equal(err, undefined, "should not error");
        assert.equal(result[0], 0, "🔴 should have no votes");
        assert.equal(result[1], 0, "🔵 should have no votes");
    });

    it("has no earnings", async () => {
        let err, result = await contract.GetEarnings(0);
        assert.equal(err, undefined, "should not error");
        assert.equal(result[0], 0, "nothing earned");
        assert.equal(result[1], 0, "nothing spent");
        assert.equal(result[2], false, "nothing to claim");
    });

    ////////////////////////////////////////////////////////////////////////////

    //
    //  Credit purchasing and withdrawal...
    //

    it("can buy credits", async () => {
        let result = await contract.BuyCredits({from: accounts[0], value: from_credits("1000")});
        assert.notEqual(result.tx, undefined);

        let balance = await contract.GetCreditBalance();
        assert.equal(to_credits(balance), 1000);
    });

    it("cannot withdraw too many credits", async () => {
        let error;
        try {
            await contract.WithdrawCredits(from_credits("10000"));
        } catch (err) {
            error = err;
        }
        assert.notEqual(error, undefined);
        assert.isAbove(error.message.search("Not enough credits"), -1);

        let balance = await contract.GetCreditBalance();
        assert.equal(to_credits(balance), 1000);
    });

    it("can withdraw credits", async () => {
        let error;
        try {
            await contract.WithdrawCredits(from_credits("1000"));
        } catch (err) {
            error = err;
        }
        assert.equal(error, undefined);

        let balance = await contract.GetCreditBalance();
        assert.equal(to_credits(balance), 0);
    });

    ////////////////////////////////////////////////////////////////////////////

    //
    // Simple round.
    //

    it("can play a simple round", async () => {
        const gamers = {
            "a": accounts[1],
            "b": accounts[2],
            "c": accounts[3],
            "d": accounts[4],
        };

        for (const [n, acct] of Object.entries(gamers)) {
            let result = await contract.BuyCredits({from: acct, value: from_credits("1000")});
            assert.notEqual(result.tx, undefined);

            let balance = await contract.GetCreditBalance({from: acct});
            assert.equal(to_credits(balance), 1000);
        }

        let gid = await contract.GetCurrentGame();
        let err, result = await contract.GetGameTotals(gid);
        assert.equal(err, undefined, "should not error");
        assert.equal(to_credits(result[0]), 0, "🔴 should have no votes");
        assert.equal(to_credits(result[1]), 0, "🔵 should have no votes");

        contract.CastVote(from_credits("100"), VOTE_RED, {from: gamers["a"]});
        contract.CastVote(from_credits("100"), VOTE_RED, {from: gamers["b"]});
        contract.CastVote(from_credits("100"), VOTE_BLUE, {from: gamers["c"]});

        err, result = await contract.GetGameTotals(gid);
        assert.equal(err, undefined, "should not error");
        assert.equal(to_credits(result[0]), 200, "🔴 should have 200");
        assert.equal(to_credits(result[1]), 100, "🔵 should have 100");

        await finishCurrentRound("hang tight, moving to the next game ...");

        err, result = await contract.GetGameTotals(gid);
        assert.equal(err, undefined, "should not error");
        assert.equal(to_credits(result[0]), 200, "🔴 should have 200");
        assert.equal(to_credits(result[1]), 100, "🔵 should have 100");

        // Validate that blue got 0 earnings for this round [gamer "c"]
        err, result = await contract.GetEarnings(gid, {from: gamers["c"]});
        assert.equal(err, undefined, "should not error");
        assert.equal(to_credits(result[0]), 0, "nothing earned");
        assert.equal(to_credits(result[1]), 100, "spent 100");
        assert.equal(result[2], false, "no claim needed");

        // Validate what each player in red earned. Blue has 100 of reward to
        // split up and red is sorted in the ratio of 100 and 100.
        err, result = await contract.GetEarnings(gid, {from: gamers["a"]});
        assert.equal(err, undefined, "should not error");
        assert.equal(to_credits(result[0]), 100 + (100 * (100.0 / 200.0)), "earned bet ratio of blue");
        assert.equal(to_credits(result[1]), 100, "spent 100");
        assert.equal(result[2], false, "not claimed yet");

        for (gamer of [gamers["a"], gamers["b"]]) {
            const old_balance = await contract.GetCreditBalance({from: gamer});
            result = await contract.ClaimEarnings(gid, {from: gamer});
            assert.notEqual(result.tx, undefined);
            const new_balance = await contract.GetCreditBalance({from: gamer});
            assert.equal(to_credits(old_balance), 900);
            assert.equal(to_credits(new_balance), 900 + 100 + apply_fee(50));
        }

        // Owner should collect 0.2% as a fee.
        const owner_balance = await contract.GetCreditBalance({from: owner_acct});
        assert.equal(to_credits(owner_balance), 0.0);
    });
});
