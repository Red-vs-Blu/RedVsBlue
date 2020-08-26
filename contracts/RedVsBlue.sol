pragma solidity >=0.4.22 <0.8.0;

/*
 *  Idea - RedVsBlue is a one-side-wins-it-all voting game for degens.
 *
 *  There are two sides, Red, and Blue. You pick which one you want and cast
 *  a vote for the corresponding side. Each poll runs for some specified amount
 *  of time - this can be done daily or weekly by the contract owner.
 *
 *  The contract address collects 0.2% (0.002) of the voted total for sponsoring
 *  the next red-vs-blue poll.
 *
 *  The voting ends after the specified interval and people who have bet on the
 *  winning side are paid out per the following math:
 *
 *  u0 = user's bet on the winning team
 *  w = winning total bets
 *  l = losing total bets (l < w!)
 *
 *  fee = 0.002                             // .2% fee for contract maintenence
 *  profit = (u0 / w) * ((1.0 - fee) * l)
 *  fees   = (u0 / w) * fee * l
 *
 *  In the event of a tie (oh so rare!), we flip a coin and truly leave things
 *  to lady luck.
 *
 *  TODO:
 *  =====
 *  As it stands, one address can only make one vote. This is likely ok.
 *
 *  Not sure how we can deploy the PeriodicPoll each period automatically once
 *  a poll ends. This might have to be a service we run on VM which responds to
 *  the poll closed event and has the delegation to issue the next event etc.
 *      -> This could even be a SaaS idea for blockchain etc
 *      -> A responder for web3 events (ifttt?)
 */
contract RedVsBlue {
    enum VoteType { VOTE_RED, VOTE_BLUE }

    uint constant BLOCK_DIV = 128;

    /*
     *  A `Vote` is the core of the is contract, this corresponds to some amount
     *  of ether (or X) being bet for the specified block number. The block
     *  number is of significance since each bet that a user makes falls within
     *  a `game` which spans `BLOCK_DIV` blocks.
     */
    struct Vote {
        uint     game_id;   /* block.number / `BLOCK_DIV` */
        uint     amount;    /* credits, 1 eth = 1000 credits */
        VoteType vote_type; /* red or blue? */
    }

    /*
     *  A `Poll` represents one of the `BLOCK_DIV` block polls.
     */
    struct Poll {
        uint red_total;
        uint blue_total;
    }

    /*
     *  A `Voter` represents one player's balance, votes and amount in play.
     */
    struct Voter {
        mapping(uint => Vote[]) votes;
        mapping(uint => bool) claimed;
        uint credits;
    }

    address public owner_address;
    mapping(address => Voter) private voters;
    mapping(uint => Poll) private poll_totals;

    /*
     *  The vote broadcast will automatically encode the block number that the
     *  log was created with. This will emit the current rounds totals for the
     *  red and blue votes so any active UIs may update their values (in
     *  stream).
     */
    event VoteBoradcastEvent(uint red_amount, uint blue_amount);

    constructor() public {
        owner_address = msg.sender;
    }

    function BuyCredits() public payable returns (bool) {
        // TODO: SafeMath!
        voters[msg.sender].credits += msg.value;
        return true;
    }

    function WithdrawCredits(uint amount) public {
        require(amount <= voters[msg.sender].credits, "Not enough credits");
        voters[msg.sender].credits -= amount;
        msg.sender.transfer(amount);
    }

    function GetCreditBalance() public view returns (uint) {
        return voters[msg.sender].credits;
    }

    function GetGameTotals(uint index) public view returns (uint, uint) {
        require(index <=  (block.number / BLOCK_DIV));
        return (poll_totals[index].red_total, poll_totals[index].blue_total);
    }

    function GetEarnings(uint game_id) public view returns (uint, uint, bool) {
        uint current_game_id = block.number / BLOCK_DIV;
        require(game_id != current_game_id);

        uint earned = 0;      /* Winnings, and original investment counter */
        uint spent = 0;      /* Spend counter - loss spend only here - view only */
        bool claimed = voters[msg.sender].claimed[game_id];

        for (uint i = 0; i < voters[msg.sender].votes[game_id].length; i++) {
            uint r = poll_totals[game_id].red_total;
            uint b = poll_totals[game_id].blue_total;
            spent += voters[msg.sender].votes[game_id][i].amount;
            if (r == b) {
                earned += voters[msg.sender].votes[game_id][i].amount;
            } else if (voters[msg.sender].votes[game_id][i].vote_type == VoteType.VOTE_RED && r > b) {
                earned += ((b * voters[msg.sender].votes[game_id][i].amount) / r);
                earned += voters[msg.sender].votes[game_id][i].amount;
            } else if (voters[msg.sender].votes[game_id][i].vote_type == VoteType.VOTE_BLUE && b > r) {
                earned += ((r * voters[msg.sender].votes[game_id][i].amount) / b);
                earned += voters[msg.sender].votes[game_id][i].amount;
            }
        }
        return (earned, spent, claimed);
    }

    function ClaimEarnings(uint game_id) public {
        uint current_game_id = block.number / BLOCK_DIV;
        require(game_id != current_game_id, "Cannot claim for active round");
        require(voters[msg.sender].claimed[game_id] == false, "Double claim? naughty naughty");

        uint earned;
        uint spent;
        bool claimed;
        (earned, spent, claimed) = GetEarnings(game_id);
        require(earned > 0 && spent > 0 && !claimed, "Can't make what you don't spend");

        voters[msg.sender].claimed[game_id] = true;
        voters[msg.sender].credits += earned;
        return;
    }

    function CastVote(uint amount, VoteType vote_type) public {
        require(amount <= voters[msg.sender].credits, "Not enough credits");
        Vote memory v;
        v.game_id = block.number / BLOCK_DIV;
        v.amount = amount;
        v.vote_type = vote_type;
        if (vote_type == VoteType.VOTE_RED) {
            poll_totals[block.number / BLOCK_DIV].red_total += amount;
        } else if (vote_type == VoteType.VOTE_BLUE) {
            poll_totals[block.number / BLOCK_DIV].blue_total += amount;
        }
        voters[msg.sender].credits -= amount;
        voters[msg.sender].votes[block.number / BLOCK_DIV].push(v);
        emit VoteBoradcastEvent(
            poll_totals[block.number / BLOCK_DIV].red_total,
            poll_totals[block.number / BLOCK_DIV].blue_total);
    }
}

