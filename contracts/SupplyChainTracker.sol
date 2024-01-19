// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract SupplyChainTracker {

    event ItemQuery(string name, string description, string unit, uint volume, uint price, string currentLocation, string managedBy, uint shipmentId);

    event ShipmentQuery(uint etd, uint eta, uint atd, uint ata, string state, string origin, string destination, string currentLocation, string courier);

    event CouierHistory(string name, address courierAdd, uint[] itemIndexs);

    event ContractStateUpdated(string status);

    enum State{ PREPARE, CREATED, SIGNED, DONE }

    enum ShipmentState{ PREPARE, SIGNED, HANDED_OVER, DEPARTED, ARRIVED, DELIVERED}

    struct Item {
        string name;
        string description;
        string unit;
        uint volume;
        uint price;
        uint shipmentId;
    }

    struct StakeHolder { // A party who can be sender, recipient, buy, seller, carier, customer...
        address addr;
        string name;
    }

    struct Shipment {
        string currentLocation;
        uint[] items;
        string origin;
        string destination;
        StakeHolder courier;
        uint etd;
        uint eta;
        uint atd;
        uint ata;
        ShipmentState state; 
    }

    StakeHolder contractOwner;
    StakeHolder supplier;
    uint itemCount = 0;
    uint shipmentCount = 0;
    uint courierCount = 0;
    uint finishedCount = 0;
    mapping(uint => Item) items;
    mapping(uint => Shipment) shipments;
    mapping(address => uint[]) courierHistory;
    mapping(address => StakeHolder) couriers;
    mapping(uint => bool) isFinishedShipment; // view as queue

    State contractState = State.PREPARE;
    uint createAt;
    uint signedAt;
    uint soonestEta;
    uint latestEta;

    constructor(string memory ownerName) {
        contractOwner = StakeHolder(msg.sender, ownerName);
    }

    function addItem(string memory name, string memory description, string memory unit, uint volume, uint price) public {
        require(msg.sender == contractOwner.addr, "Only contract owner can add item to order");
        require(contractState == State.PREPARE, "Suply contract is created, cannot add new item");
        items[itemCount] = Item(name, description, unit, volume, price, 0);
        isFinishedShipment[finishedCount] = false;
        itemCount++;
        finishedCount++;   
    }

    function initSupplyContract(string memory supplierName, address supplierAddr, uint shortestAcceptibleEta, uint latestAcceptibleEta) public {
        require(msg.sender == contractOwner.addr, "Only contract owner can create Sypply contract");
        require(contractState == State.PREPARE, "Suply contract has been already created");
        contractState = State.CREATED;
        supplier = StakeHolder(supplierAddr, supplierName);
        soonestEta = shortestAcceptibleEta;
        latestEta = latestAcceptibleEta;
    }

    function signSupplyContract() public {
        require(msg.sender == supplier.addr, "Not the supplierer of this contract");
        require(contractState == State.CREATED, "Contract must be created and unsigned");
        contractState = State.SIGNED;
    }

    function queryItemDetails(uint index) public {
        Item storage item = items[index];
        if (item.shipmentId == 0) {            
            emit ItemQuery(item.name, item.description, item.unit, item.volume, item.price, "N/A", "N/A", 0);
        } else {
            Shipment storage shipment = shipments[item.shipmentId];
            string memory manageBy = shipment.courier.name;
            if (shipment.state == ShipmentState.PREPARE || shipment.state == ShipmentState.SIGNED) {
                manageBy = supplier.name;
            } else if (shipment.state == ShipmentState.DELIVERED) {
                manageBy = contractOwner.name;
            }
            emit ItemQuery(item.name, item.description, item.unit, item.volume, item.price, shipment.currentLocation, manageBy, item.shipmentId);
        }
        
    }

    function createShipment(string memory courierName, address courierAddr, string memory currentLocation, uint[] memory shipmentItems, string memory origin, string memory destination, uint etd, uint eta) public returns(uint) {
        require(msg.sender == supplier.addr, "Not the supplierer of this contract");
        require(contractState == State.SIGNED, "Contract must be signed and not done yet");
        bool valid_flag = true;
        for (uint i = 0; i < shipmentItems.length; i++) {
            uint index = shipmentItems[i];
            Item storage item = items[index];
            if (item.shipmentId != 0){
                valid_flag = false;
                break;
            }
        }
        require(valid_flag, "Item already be captured");
        // add courier
        courierHistory[courierAddr] = shipmentItems;
        couriers[courierAddr] = StakeHolder(courierAddr, courierName);
        courierCount ++;
        // add shipment
        shipments[shipmentCount] = Shipment(currentLocation, shipmentItems, origin, destination, StakeHolder(courierAddr, courierName), etd, eta, 0, 0, ShipmentState.PREPARE);
        shipmentCount++;
        for (uint i = 0; i < shipmentItems.length; i++) {
            uint index = shipmentItems[i];
            Item storage item = items[index];
            item.shipmentId = shipmentCount;
        }
        return shipmentCount;
    }

    function signShipment(uint shipmentIndex) public {
        Shipment storage shipment = shipments[shipmentIndex];
        require(msg.sender == shipment.courier.addr, "Not the courier of this shipment");
        require(shipment.state == ShipmentState.PREPARE, "Shipment has been already signed");
        shipment.state = ShipmentState.SIGNED;
    }

    function transferFromSupplierToCourier(uint shipmentIndex) public {
        Shipment storage shipment = shipments[shipmentIndex];
        require(msg.sender == shipment.courier.addr, "Not the courier of this shipment");
        require(shipment.state == ShipmentState.SIGNED, "Shipment must be signed and courier hasn't received items yet");
        shipment.state = ShipmentState.HANDED_OVER;
    }

    function updateShipmentStatus(uint shipmentIndex, string memory currentLocation, uint state) public {
        Shipment storage shipment = shipments[shipmentIndex];
        require(msg.sender == shipment.courier.addr, "Not the courier of this shipment");
        require(shipment.state == ShipmentState.SIGNED, "Shipment must be signed and courier hasn't received items yet");
        require(state > 1, "This kind of state can only be updated by Supplier");
        require(state < 5, "This kind of state can only be updated by Buyer");
        if (state == 3) {
            shipment.state = ShipmentState.DEPARTED;
            shipment.atd = block.timestamp;
        } else if (state == 4) {
            require(keccak256(bytes(currentLocation)) == keccak256(bytes(shipment.destination)), "Destination mismatch");
            shipment.state = ShipmentState.ARRIVED;
            shipment.ata = block.timestamp;
        } else {
            shipment.state = ShipmentState.HANDED_OVER;
        }
        shipment.currentLocation = currentLocation;
    }

    function receiveFromCourier(uint shipmentIndex) public {
        require(msg.sender == contractOwner.addr, "Only contract owner can create Supply contract");
        Shipment storage shipment = shipments[shipmentIndex];
        shipment.currentLocation = shipment.destination;
        shipment.state = ShipmentState.DELIVERED;
        StakeHolder storage courier = shipment.courier;
        uint [] storage itemIds = courierHistory[courier.addr];
        for(uint i=0; i < itemIds.length; i++){
            finishedCount --;
            delete isFinishedShipment[itemIds[i]];
        }
    }

    function queryShipmenDetails(uint shipmentIndex) public {
        Shipment storage shipment = shipments[shipmentIndex];
        string memory state = "N/A";
        if (shipment.state == ShipmentState.PREPARE) {
            state = "PREPARE";
        } else if (shipment.state == ShipmentState.SIGNED) {
            state = "SIGNED";
        } else if (shipment.state == ShipmentState.HANDED_OVER) {
            state = "HANDED_OVER";
        } else if (shipment.state == ShipmentState.DEPARTED) {
            state = "DEPARTED";
        } else if (shipment.state == ShipmentState.ARRIVED) {
            state = "ARRIVED";
        }  else if (shipment.state == ShipmentState.DELIVERED) {
            state = "DELIVERED";
        }
        emit ShipmentQuery(shipment.etd, shipment.eta, shipment.atd, shipment.ata, state, shipment.origin, shipment.destination, shipment.currentLocation, shipment.courier.name);
    }

    function queryCourierHolding(address courierAddr) public{
        // For getting courier name
        StakeHolder storage courier = couriers[courierAddr];
        // For get holding items
        uint[] storage itemIds = courierHistory[courierAddr];
        emit CouierHistory(courier.name, courierAddr, itemIds);
    }

    function getItemCount() public view returns (uint){
    return itemCount;
    }

    function getShipmentCount() public view returns (uint){
        return shipmentCount;
    }
    
    function getCourierCount() public view returns (uint){
        return courierCount;
    }

    function getOwner() public view returns (address){
        return contractOwner.addr;
    }

    function getSupplier() public view returns (address){
        return supplier.addr;
    }

    function checkSatisfiedContrast() public view returns (bool){
        bool is_satisfied = true;
        if (finishedCount >0){
            return false;
        }
        return is_satisfied;
    }
}