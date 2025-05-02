pragma solidvm 11.5;

import "../Utils/Utils.sol";

abstract contract MercataGnosisBridge is Utils {
    enum AssetStatus {
        NULL,
        ACTIVE,
        PENDING_REDEMPTION,
        RETIRED,
        MAX
    }

    address public owner;
    address public burnerAddress = address(0x6ec8bbe4a5b87be18d443408df43a45e5972fa1b); // burner account
    bool public isActive = true;

    address public gnosisWethStAddress;

    mapping(string => uint) public hashExists;

    event GnosisWethStBridgeHashAdded(address userAddress, string txhash, string amount);
    event MintedGnosisWethSt(address user, string username, uint amount);
    event BurnedGnosisWethSt(address user, string username, string baseAddress, uint amount);

    modifier onlyOwner() {
        require(owner == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    modifier requireActive() {
        require(isActive, "MercataGnosisBridge is not active");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }

    function deactivate() public onlyOwner requireActive {
        isActive = false;
    }

    function activate() public onlyOwner {
        require(!isActive, "Cannot activate when active");
        isActive = true;
    }

    function mintGnosisWethSt(address _userAddress, uint _amount, string _txHash) external onlyOwner requireActive {
        require(_amount > 0, "Must mint some GnosisWETHST");
        require(hashExists[_txHash] == 1, "Hash doesn't exists");
        hashExists[_txHash] = 2;
        Mintable(gnosisWethStAddress).mintNewUnits(_amount);
        Asset(UTXO(Redeemable(Mintable(gnosisWethStAddress)))).automaticTransfer(_userAddress, 0.000000000000000001, _amount, block.number);
        emit MintedGnosisWethSt(_userAddress, getCommonName(_userAddress), _amount);
    }

    function addGnosisWethStHash(address _userAddress, string _txHash, string _amount) external requireActive {
        require(hashExists[_txHash] == 0, "Hash already exists");
        hashExists[_txHash] = 1;
        emit GnosisWethStBridgeHashAdded(_userAddress, _txHash, _amount);
    }

    function burnGnosisWethSt(
        address[] _gnosisWethStAddresses,
        uint _quantity,
        string _baseAddress
    ) requireActive() external returns (uint) {
        require(_gnosisWethStAddresses.length > 0, "Pass at least one GnosisWETHST token address");
        uint gnosisWethStAmountOwed = _quantity;
        uint gnosisWethStAmountNet = gnosisWethStAmountOwed;
        uint gnosisWethStQuantity = 0;
        uint transferNumber = 0;

        for (uint j = 0; j < _gnosisWethStAddresses.length; j++) {
            address currentGnosisWethStAddress = _gnosisWethStAddresses[j];
            Asset gnosisWethStAsset = Asset(currentGnosisWethStAddress);
            require(gnosisWethStAsset.root == gnosisWethStAddress.root, "Asset is not a GnosisWETHST asset");
            require(gnosisWethStAsset.ownerCommonName() == getCommonName(msg.sender), "Purchaser doesn't own this GnosisWETHST asset");

            gnosisWethStQuantity = gnosisWethStAsset.quantity();
            transferNumber = (uint(string(currentGnosisWethStAddress), 16) + j + block.timestamp) % 1000000;

            gnosisWethStAsset.attachSale();
            if (gnosisWethStQuantity > gnosisWethStAmountNet) {
                gnosisWethStAsset.transferOwnership(burnerAddress, gnosisWethStAmountNet, false, transferNumber, 0.000000000000000001);
                gnosisWethStAsset.closeSale();
                gnosisWethStAmountNet = 0;
            } else {
                gnosisWethStAsset.transferOwnership(burnerAddress, gnosisWethStQuantity, false, transferNumber, 0.000000000000000001);
                gnosisWethStAmountNet -= gnosisWethStQuantity;
            }

            if (gnosisWethStAmountNet == 0) {
                break;
            }
        }
        // require(gnosisWethStAmountNet == 0, "Your GnosisWETHST balance is not high enough to cover the repayment."); // Allow partial repayments

        uint gnosisWethStAmountRepaid = gnosisWethStAmountOwed - gnosisWethStAmountNet;
        emit BurnedGnosisWethSt(msg.sender, getCommonName(msg.sender), _baseAddress, gnosisWethStAmountRepaid);
    }
}