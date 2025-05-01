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

    address public gnosisSt;

    mapping(string => uint) public hashExists;

    event GnosisBridgeHashAdded(address userAddress, string txhash, string amount);
    event MintedGnosis(address user, string username, uint amount);
    event BurnedGnosis(address user, string username, string baseAddress, uint amount);

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

    function mintGnosis(address _userAddress, uint _amount, string _txHash) external onlyOwner requireActive {
        require(_amount > 0, "Must mint some Gnosis");
        require(hashExists[_txHash] == 1, "Hash doesn't exists");
        hashExists[_txHash] = 2;
        Mintable(gnosisSt).mintNewUnits(_amount);
        Asset(UTXO(Redeemable(Mintable(gnosisSt)))).automaticTransfer(_userAddress, 0.000000000000000001, _amount, block.number);
        emit MintedGnosis(_userAddress, getCommonName(_userAddress), _amount);
    }

    function addHash(address _userAddress, string _txHash, string _amount) external requireActive {
        require(hashExists[_txHash] == 0, "Hash already exists");
        hashExists[_txHash] = 1;
        emit GnosisBridgeHashAdded(_userAddress, _txHash, _amount);
    }

    function burnGnosis(
        address[] _gnosisAddresses,
        uint _quantity,
        string _baseAddress
    ) requireActive() external returns (uint) {
        require(_gnosisAddresses.length > 0, "Pass at least one Gnosis token address");
        uint gnosisAmountOwed = _quantity;
        uint gnosisAmountNet = gnosisAmountOwed;
        uint gnosisQuantity = 0;
        uint transferNumber = 0;

        for (uint j = 0; j < _gnosisAddresses.length; j++) {
            address gnosisAddress = _gnosisAddresses[j];
            Asset gnosisAsset = Asset(gnosisAddress);
            require(gnosisAsset.root == gnosisSt.root, "Asset is not a Gnosis asset");
            require(gnosisAsset.ownerCommonName() == getCommonName(msg.sender), "Purchaser doesn't own this Gnosis asset");

            gnosisQuantity = gnosisAsset.quantity();
            transferNumber = (uint(string(gnosisAddress), 16) + j + block.timestamp) % 1000000;

            gnosisAsset.attachSale();
            if (gnosisQuantity > gnosisAmountNet) {
                gnosisAsset.transferOwnership(burnerAddress, gnosisAmountNet, false, transferNumber, 0.000000000000000001);
                gnosisAsset.closeSale();
                gnosisAmountNet = 0;
            } else {
                gnosisAsset.transferOwnership(burnerAddress, gnosisQuantity, false, transferNumber, 0.000000000000000001);
                gnosisAmountNet -= gnosisQuantity;
            }

            if (gnosisAmountNet == 0) {
                break;
            }
        }
        // require(gnosisAmountNet == 0, "Your gnosisS balance is not high enough to cover the repayment."); // Allow partial repayments

        uint gnosisAmountRepaid = gnosisAmountOwed - gnosisAmountNet;
        emit BurnedGnosis(msg.sender, getCommonName(msg.sender), _baseAddress, gnosisAmountRepaid);
    }
}