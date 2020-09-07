
pragma solidity ^0.5.5;

import '@openzeppelin/contracts/lifecycle/Pausable.sol';
import '@openzeppelin/contracts/ownership/Ownable.sol';
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

import "../library/SafeERC20.sol";
import "../interface/IERC20.sol";

/// @title DegoOpenSale Contract

contract DegoOpenSale is Pausable,Ownable {
    using SafeMath for uint256;
    using Address for address;

    struct condition {
        uint256 price;          //_dego per eth
        uint256 limitFund;      //a quota
        uint256 startTime;      //the stage start time
        uint256 maxSoldAmount;  //the stage max sold amount
    }

    //
    uint8 public constant _whiteListStage1 = 1;
    uint8 public constant _whiteListStage5 = 5;
    //
    /// All deposited ETH will be instantly forwarded to this address.
    address payable public _teamWallet = 0x6666666666666666666666666666666666666666;
    
    /// IERC20 compilant _dego token contact instance
    IERC20 public _dego = IERC20(0x6666666666666666666666666666666666666666);

    /// tags show address can join in open sale
    mapping (uint8 =>  mapping (address => bool)) public _fullWhiteList;

    //the stage condition map
    mapping (uint8 => condition) public _stageCondition;

    //the user get fund per stage
    mapping (uint8 =>  mapping (address => uint256) ) public _stageFund;


    //the stage had sold amount
    mapping (uint8 => uint256) public _stageSoldAmount;
    
    /*
     * EVENTS
     */
    event eveNewSale(address indexed destAddress, uint256 ethCost, uint256 gotTokens);
    event eveClaim(address indexed destAddress, uint256 gotTokens);
    event eveTeamWallet(address wallet);



    /// @dev valid the address
    modifier validAddress( address addr ) {
        require(addr != address(0x0));
        require(addr != address(this));
        _;
    }

    constructor()
        public
    {
        pause();

        // uint256 testRate = 100;
        // uint256 testRate2 = 1000;

        // setCondition(1,3500 * testRate2,10*1e18/testRate, now,          525000*1e18);
        // setCondition(2,2500 * testRate2,5 *1e18/testRate, now + 1 days, 375000*1e18);
        // setCondition(3,2000 * testRate2,5 *1e18/testRate, now + 1 days, 600000*1e18);
        // setCondition(4,1500 * testRate2,5 *1e18/testRate, now + 1 days, 450000*1e18);
        // setCondition(5,1500 * testRate2,2 *1e18/testRate, now + 3 days, 150000*1e18);

        setCondition(1,3500 ,10*1e18, now,          525000*1e18);
        setCondition(2,2500 ,5 *1e18, now + 1 days, 375000*1e18);
        setCondition(3,2000 ,5 *1e18, now + 1 days, 600000*1e18);
        setCondition(4,1500 ,5 *1e18, now + 1 days, 450000*1e18);
        setCondition(5,1500 ,2 *1e18, now + 3 days, 150000*1e18);
        
    }


    /**
    * @dev for set team wallet
    */
    function setTeamWallet(address payable wallet) public 
        onlyOwner 
    {
        require(wallet != address(0x0));

        _teamWallet = wallet;

        emit eveTeamWallet(wallet);
    }

    /// @dev set the sale condition for every stage;
    function setCondition(
    uint8 stage,
    uint256 price,
    uint256 limitFund,
    uint256 startTime,
    uint256 maxSoldAmount )
        internal
        onlyOwner
    {

        _stageCondition[stage].price = price;
        _stageCondition[stage].limitFund =limitFund;
        _stageCondition[stage].startTime= startTime;
        _stageCondition[stage].maxSoldAmount=maxSoldAmount;
    }



    /// @dev set the sale start time for every stage;
    function setStartTime(uint8 stage,uint256 startTime )
        public
        onlyOwner
    {
        _stageCondition[stage].startTime = startTime;
    }

    /// @dev batch set quota for user admin
    /// if openTag <=0, removed 
    function setWhiteList(uint8 stage, address[] calldata users, bool openTag)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < users.length; i++) {
            _fullWhiteList[stage][users[i]] = openTag;
        }
    }

    /// @dev batch set quota for early user quota
    /// if openTag <=0, removed 
    function addWhiteList(uint8 stage, address user, bool openTag)
        external
        onlyOwner
    {
        _fullWhiteList[stage][user] = openTag;
    }

    /**
     * @dev If anybody sends Ether directly to this  contract, consider he is getting DeGo token
     */
    function () external payable {
        buyDeGo(msg.sender);
    }

    //
    function getStage( ) view public returns(uint8) {

        for(uint8 i=1; i<6; i++){
            uint256 startTime = _stageCondition[i].startTime;
            if(now >= startTime && _stageSoldAmount[i] < _stageCondition[i].maxSoldAmount ){
                return i;
            }
        }

        return 0;
    }

    //
    function conditionCheck( address addr ) view internal  returns(uint8) {
    
        uint8 stage = getStage();
        require(stage!=0,"stage not begin");
        
        uint256 fund = _stageFund[stage][addr];
        require(fund < _stageCondition[stage].limitFund,"stage fund is full ");

        return stage;
    }

    /// @dev Exchange msg.value ether to Dego for account recepient
    /// @param receipient Dego tokens receiver
    function buyDeGo(address receipient) 
        internal 
        whenNotPaused  
        validAddress(receipient)
        returns (bool) 
    {
        // Do not allow contracts to game the system

        require(tx.gasprice <= 500000000000 wei);

        uint8 stage = conditionCheck(receipient);
        if(stage==_whiteListStage1 || stage==_whiteListStage5 ){  
            require(_fullWhiteList[stage][receipient],"your are not in the whitelist ");
        }

        doBuy(receipient, stage);

        return true;
    }


    /// @dev Buy DeGo token normally
    function doBuy(address receipient, uint8 stage) internal {
        // protect partner quota in stage one
        uint256 value = msg.value;
        uint256 fund = _stageFund[stage][receipient];
        fund = fund.add(value);
        if (fund > _stageCondition[stage].limitFund ) {
            uint256 refund = fund.sub(_stageCondition[stage].limitFund);
            value = value.sub(refund);
            msg.sender.transfer(refund);
        }
        
        uint256 soldAmount = _stageSoldAmount[stage];
        uint256 tokenAvailable = _stageCondition[stage].maxSoldAmount.sub(soldAmount);
        require(tokenAvailable > 0);

        uint256 costValue = 0;
        uint256 getTokens = 0;

        // all conditions has checked in the caller functions
        uint256 price = _stageCondition[stage].price;
        getTokens = price * value;
        if (tokenAvailable >= getTokens) {
            costValue = value;
        } else {
            costValue = tokenAvailable.div(price);
            getTokens = tokenAvailable;
        }

        if (costValue > 0) {
        
            _stageSoldAmount[stage] = _stageSoldAmount[stage].add(getTokens);
            _stageFund[stage][receipient]=_stageFund[stage][receipient].add(costValue);

            _dego.mint(msg.sender, getTokens);   

            emit eveNewSale(receipient, costValue, getTokens);             
        }

        // not enough token sale, just return eth
        uint256 toReturn = value.sub(costValue);
        if (toReturn > 0) {
            msg.sender.transfer(toReturn);
        }

    }

    // get sale eth 
    function seizeEth() external  {
        uint256 _currentBalance =  address(this).balance;
        _teamWallet.transfer(_currentBalance);
    }
    

}