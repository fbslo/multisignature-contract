pragma solidity ^0.8.1;
// SPDX-License-Identifier: MIT

contract MultiSignature {
    address tokenContract;
    uint public ownersLength;
    mapping(address => bool) public isOwner;
    mapping(address => address) public owners;
    mapping(string => bool) public alreadyApproved;
    mapping(address => bool) isSigUsed;
    mapping(uint256 => bool) isNonceUsed;

    event minted(address to, uint256 amount, string _reference);
    event ownerAdded(address owner);
    event ownerRemoved(address owner);
    
    constructor(address[] memory _owners, address _tokenContract) {
        require(_owners.length > 0, "Owners required");
        require(_owners.length <= 40, "Max 40 owners");
        
        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];

            require(owner != address(0), "Invalid owner");
            require(!isOwner[owner], "Owner not unique");

            isOwner[owner] = true;
            owners[owner] = owner;
        }
        ownersLength = _owners.length;
        tokenContract = _tokenContract;
    }
    
    function mint(bytes[] memory _signatures, address _to, uint256 _amount, string memory _reference) public {
        require(!alreadyApproved[_reference], 'Reference already used');
        require(isApprovedMint(_signatures, _to, _amount, _reference),  'Signatures not valid/threshold not reached');
        alreadyApproved[_reference] = true;
        ERC20 erc20 = ERC20(tokenContract);
        erc20.mint(_to, _amount);
        emit minted(_to, _amount, _reference);
    }
    
    function modifyOwner(bytes[] memory _signatures, address _owner, bool  _added) public {
        require(!isNonceUsed[_nonce], 'Nonce already used');
        if (_added == true){ //we are adding new owner
            require(!isOwner[_owner], 'Owner already exists');
        } else { 
            require(isOwner[_owner], 'Owner does not exists yet');
        }
        require(isApprovedOwner(_signatures, _owner, _added),  'Signatures not valid/threshold not reached');
        isNonceUsed[_nonce] = true;
        if (_added == true){
            require(ownersLength < 40, 'Already 40 owners');
            ownersLength += 1;
            isOwner[_owner] = true;
            owners[_owner] = _owner;
            emit ownerAdded(_owner);
        } else {
            ownersLength -= 1;
            isOwner[_owner] = false;
            delete owners[_owner];
            emit ownerRemoved(_owner);
        }
    }
    
    function isApprovedMint(bytes[] memory _signatures, address _to, uint256 _amount, string memory _reference) public returns(bool) {
        uint isApproved = 0;
        address[40] memory signers; //max 40 signers
        for (uint i = 0; i < _signatures.length; i++) {
            bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_to, _amount, _reference))));
            address signer = recoverSigner(hash, _signatures[i]);
            if (isOwner[signer] && !isSigUsed[signer]){
                isSigUsed[signer] = true;
                signers[i] = signer;
                isApproved++;
            }
        }
        //clear used signatures and clear signers array
        for (uint i = 0; i < _signatures.length; i++){
            isSigUsed[signers[i]] = false;
            delete signers[i];
        }
        if (isApproved >= (ownersLength * 80) / 100){
            return true;
        } else {
            return false;
        }
    }
    
    //_added is either true if we are adding new owner, or false if we are removing it
    function isApprovedOwner(bytes[] memory _signatures, address _owner, bool _added) public returns (bool) {
        uint isApproved = 0;
        address[40] memory signers;
        for (uint i = 0; i < _signatures.length; i++) {
            bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_owner, _added, _nonce))));
            address signer = recoverSigner(hash, _signatures[i]);
            if (isOwner[signer] && !isSigUsed[signer]){
                isSigUsed[signer] = true;
                signers[i] = signer;
                isApproved++;
            }
        }
         //clear used signatures and clear signers array
        for (uint i = 0; i < _signatures.length; i++){
            isSigUsed[signers[i]] = false;
            delete signers[i];
        }
        if (isApproved >= (ownersLength * 80) / 100){
            return true;
        } else {
            return false;
        }
    }
    
    //Once migration is approved, new address will receive minter role and minter role will be removed from this contract.
    function migrate(bytes[] memory _signatures, address _newMinter) public {
        require(isApprovedMigration(_signatures, _newMinter), 'Signatures not valid/threshold not reached');
        ERC20 token = ERC20(tokenContract);
        token.addMinter(_newMinter);
        bool isMinterAdded = token.isMinter(_newMinter);
        require(isMinterAdded, "New minter was not addded");
        token.removeMinter(address(this));
        require(!token.isMinter(address(this)), "Old minter was not removed");
    }
    
    function isApprovedMigration(bytes[] memory _signatures, address _newMinter) public returns(bool) {
        uint isApproved = 0;
        address[40] memory signers; //max 40 signers
        for (uint i = 0; i < _signatures.length; i++) {
            bytes32 hash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_newMinter))));
            address signer = recoverSigner(hash, _signatures[i]);
            if (isOwner[signer] && !isSigUsed[signer]){
                isSigUsed[signer] = true;
                signers[i] = signer;
                isApproved++;
            }
        }
        //clear used signatures and clear signers array
        for (uint i = 0; i < _signatures.length; i++){
            isSigUsed[signers[i]] = false;
            delete signers[i];
        }
        if (isApproved >= (ownersLength * 80) / 100){
            return true;
        } else {
            return false;
        }
    }
    
    //Recover signer from signature
    function recoverSigner(bytes32 hash, bytes memory _signature) private pure returns (address){
        bytes32 r;
        bytes32 s;
        uint8 v;
    
        if (_signature.length != 65) {
            return (address(0));
        }
        
        assembly {
            r := mload(add(_signature, 0x20))
            s := mload(add(_signature, 0x40))
            v := byte(0, mload(add(_signature, 0x60)))
        }
        
        if (v < 27) {
            v += 27;
        }
        
        if (v != 27 && v != 28) {
            return (address(0));
        } else {
            return ecrecover(hash, v, r, s);
        }
    }
    
    function getMessageHash(address _to, uint256 _amount, string memory _reference) public pure returns(bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", keccak256(abi.encodePacked(_to, _amount, _reference))));
    }
}

interface ERC20 {
    function totalSupply() external;
    function balanceOf(address _owner) external;
    function transfer(address _to, uint _value) external;
    function transferFrom(address _from, address _to, uint _value) external;
    function approve(address _spender, uint _value) external;
    function allowance(address _owner, address _spender) external;
    function decimals() external;
    function mint(address _to, uint256 _amount) external;
    event Approval(address indexed _owner, address indexed _spender, uint _value);
}
