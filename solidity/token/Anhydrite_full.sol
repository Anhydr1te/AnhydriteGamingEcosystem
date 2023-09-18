// SPDX-License-Identifier: Apache License 2.0
/*
 * Copyright (C) 2023 Anhydrite Gaming Ecosystem
 *
 * This code is part of the Anhydrite Gaming Ecosystem.
 *
 * ERC-20 Token: Anhydrite ANH
 * Network: Binance Smart Chain
 * Website: https://anh.ink
 * GitHub: https://github.com/Anhydr1te/AnhydriteGamingEcosystem
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that explicit attribution to the original code and website
 * is maintained. For detailed terms, please contact the Anhydrite Gaming Ecosystem team.
 *
 * Portions of this code are derived from OpenZeppelin contracts, which are licensed
 * under the MIT License. Those portions are not subject to this license. For details,
 * see https://github.com/OpenZeppelin/openzeppelin-contracts
 *
 * This code is provided as-is, without warranty of any kind, express or implied,
 * including but not limited to the warranties of merchantability, fitness for a 
 * particular purpose, and non-infringement. In no event shall the authors or 
 * copyright holders be liable for any claim, damages, or other liability, whether 
 * in an action of contract, tort, or otherwise, arising from, out of, or in connection 
 * with the software or the use or other dealings in the software.
 */
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title BaseUtility Abstract Contract
 * @dev This abstract contract provides base functionalities for interacting with a proxy contract.
 *      It includes helper methods for setting, querying, and interacting with the proxy contract.
 * 
 *      The '_proxy' state variable stores the Ethereum address of the proxy contract that adheres to the IProxy interface.
 * 
 *      Functions include:
 *      - getProxyAddress: To publicly get the Ethereum address of the proxy contract.
 *      - _setProxyContract: To set or update the proxy contract address.
 *      - _proxyContract: To get the current proxy contract address.
 *      - _isProxyOwner: To check if an address is an owner of the proxy contract.
 *      - _checkIProxyContract: To validate if an address is a smart contract that implements the IProxy interface.
 */
abstract contract BaseUtility {
    
    // Proxy contract interface
    IProxy private _proxy;

    // Returns the Ethereum address of the proxy contract.
    function getProxyAddress() public view returns (address) {
        return address(_proxy);
    }

    /*
     * Internal function to update the proxy contract address.
     * This function is used to set a new address for the proxy contract and 
     * it takes the new address as an argument. It assumes the address adheres to the IProxy interface.
     * The internal state variable '_proxy' is then updated with this new address.
     */
    function _setProxyContract(address newProxy) internal {
        _proxy = IProxy(newProxy);
    }

    /*
     * Internal view function to get the current proxy contract address.
     * This function returns the current address stored in the '_proxy' state variable.
     * This is a 'view' function, meaning it doesn't modify the state and is free to call.
     */
    function _proxyContract() internal view returns (IProxy) {
        return _proxy;
    }

    // Checks if an address is an owner of the proxy contract, as per the proxy contract's own rules.
    function _isProxyOwner(address senderAddress) internal view returns (bool) {
        return _proxyContract().isProxyOwner(senderAddress);
    }

    // Checks if an address is a smart contract that implements the IProxy interface.
    function _checkIProxyContract(address contractAddress) internal view returns (bool) {
        if (contractAddress.code.length > 0) {
            IERC165 targetContract = IERC165(contractAddress);
            return targetContract.supportsInterface(type(IProxy).interfaceId);
        }
        return false;
    }
}

// IProxy interface defines the methods a Proxy contract should implement.
interface IProxy {
    // Returns the core ERC20 token of the project
    function getCoreToken() external view returns (IERC20);

    // Returns the address of the current implementation (logic contract)
    function implementation() external view returns (address);

    // Returns the number of tokens needed to become an owner
    function getTokensNeededForOwnership() external view returns (uint256);

    // Returns the total number of owners
    function getTotalOwners() external view returns (uint256);

    // Checks if an address is a proxy owner (has voting rights)
    function isProxyOwner(address tokenAddress) external view returns (bool);

    // Checks if an address is an owner
    function isOwner(address account) external view returns (bool);

    // Returns the balance of an owner
    function getBalanceOwner(address owner) external view returns (uint256);

    // Checks if an address is blacklisted
    function isBlacklisted(address account) external view returns (bool);

    // Checks if the contract is stopped
    function isStopped() external view returns (bool);
    
    // Increases interest for voting participants
    function increase(address[] memory addresses) external;
}


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 */
abstract contract Ownable is BaseUtility {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(msg.sender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    // Modifier that checks whether you are among the owners of the proxy smart contract and whether you have the right to vote
    modifier onlyOwner() {
        if (address(_proxyContract()) != address(0) && _proxyContract().getTotalOwners() > 0) {
            require(_isProxyOwner(msg.sender), "Ownable: caller is not the proxy owner");
        } else {
            require(_owner == msg.sender, "Ownable: caller is not the owner");
        }
        _;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


/*
 * A smart contract serving as a utility layer for voting and ownership management.
 * It extends Ownable contract and interfaces with an external Proxy contract.
 * The contract provides:
 * 1. Vote management with upvotes and downvotes, along with vote expiration checks.
 * 2. Owner checks that allow both the contract owner and proxy contract owners to execute privileged operations.
 * 3. Interface compatibility checks for connected proxy contracts.
 * 4. Renunciation of ownership is explicitly disabled.
 */
abstract contract VoteUtility is Ownable {

    // Voting structure
    struct VoteResult {
        address[] isTrue;
        address[] isFalse;
        uint256 timestamp;
    }

    // Internal function to increases interest for VoteResult participants
    function _increaseArrays(VoteResult memory result) internal {
        address[] memory isTrue = result.isTrue;
        address[] memory isFalse = result.isFalse;

        uint256 length1 = isTrue.length;
        uint256 length2 = isFalse.length;
        uint256 totalLength = length1 + length2;

        address[] memory merged = new address[](totalLength);
        for (uint256 i = 0; i < length1; i++) {
            merged[i] = isTrue[i];
        }

        for (uint256 j = 0; j < length2; j++) {
            merged[length1 + j] = isFalse[j];
        }

        _increase(merged);
    }

    // Calls the 'increase' method on the proxy contract to handle voting participants
    function _increase(address[] memory owners) internal {
        if (address(_proxyContract()) != address(0)) {
            _proxyContract().increase(owners);
        }
    }

    /*
     * Internal Function: _votes
     * - Purpose: Records a vote for a given voting result and returns vote counts.
     * - Arguments:
     *   - result: The voting result to update.
     *   - vote: Boolean representing the vote (true for upvote, false for downvote).
     * - Returns:
     *   - Number of upvotes.
     *   - Number of downvotes.
     *   - Total number of owners.
     */
    function _votes(VoteResult storage result, bool vote) internal returns (uint256, uint256, uint256) {
        uint256 _totalOwners = 1;
        if (address(_proxyContract()) != address(0)) {
            _totalOwners = _proxyContract().getTotalOwners();
        } 
        if (vote) {
            result.isTrue.push(msg.sender);
        } else {
            result.isFalse.push(msg.sender);
        }
        return (result.isTrue.length, result.isFalse.length, _totalOwners);
    }

    // Internal function to reset the voting result to its initial state
    function _resetVote(VoteResult storage vote) internal {
        vote.isTrue = new address[](0);
        vote.isFalse = new address[](0);
        vote.timestamp = 0;
    }
    
    /*
     * Internal Function: _completionVoting
     * - Purpose: Marks the end of a voting process by increasing vote counts and resetting the VoteResult.
     * - Arguments:
     *   - result: The voting result to complete.
     */
    function _completionVoting(VoteResult storage result) internal {
        _increaseArrays(result);
        _resetVote(result);
    }

    /*
     * Internal Function: _closeVote
     * - Purpose: Closes the voting process after a set period and resets the voting structure.
     * - Arguments:
     *   - vote: The voting result to close.
     */
    function _closeVote(VoteResult storage vote) internal canClose(vote.timestamp) {
        if (address(_proxyContract()) != address(0)) {
            address[] memory newArray = new address[](1);
            newArray[0] = msg.sender;
            _increase(newArray);
        }
        _resetVote(vote);
    }
    
    // Internal function to check if an address has already voted in a given VoteResult
    function _hasOwnerVoted(VoteResult memory result, address targetAddress) internal pure returns (bool) {
        for (uint256 i = 0; i < result.isTrue.length; i++) {
            if (result.isTrue[i] == targetAddress) {
                return true;
            }
        }
        for (uint256 i = 0; i < result.isFalse.length; i++) {
            if (result.isFalse[i] == targetAddress) {
                return true;
            }
        }
        return false;
    }

    // Modifier to check if enough time has passed to close the voting
    modifier canClose(uint256 timestamp) {
        require(block.timestamp >= timestamp + 3 days, "VoteUtility: Voting is still open");
        _;
    }

    // Modifier to ensure an address has not voted before in a given VoteResult
    modifier hasNotVoted(VoteResult memory result) {
        require(!_hasOwnerVoted(result, msg.sender), "VoteUtility: Already voted");
        _;
    }
}


/*
 * A smart contract that extends the UtilityVotingAndOwnable contract to provide financial management capabilities.
 * The contract allows for:
 * 1. Withdrawal of BNB to a designated address, which is the implementation address of an associated Proxy contract.
 * 2. Withdrawal of ERC20 tokens to the same designated address.
 * 3. Transfer of ERC721 tokens (NFTs) to the designated address.
 * All financial operations are restricted to the contract owner.
 */
abstract contract FinanceManager is Ownable {

    /**
     * @dev Withdraws BNB from the contract to a designated address.
     * @param amount Amount of BNB to withdraw.
     */
    function withdrawMoney(uint256 amount) external onlyOwner {
        address payable recipient = payable(_recepient());
        require(address(this).balance >= amount, "FinanceManager: Contract has insufficient balance");
        recipient.transfer(amount);
    }

    /**
     * @dev Withdraws ERC20 tokens from the contract.
     * @param _tokenAddress The address of the ERC20 token contract.
     * @param _amount The amount of tokens to withdraw.
     */
    function withdrawERC20Tokens(address _tokenAddress, uint256 _amount) external onlyOwner {
        IERC20 token = IERC20(_tokenAddress);
        require(token.balanceOf(address(this)) >= _amount, "FinanceManager: Not enough tokens on contract balance");
        token.transfer(_recepient(), _amount);
    }

    /**
     * @dev Transfers an ERC721 token from this contract.
     * @param _tokenAddress The address of the ERC721 token contract.
     * @param _tokenId The ID of the token to transfer.
     */
    function withdrawERC721Token(address _tokenAddress, uint256 _tokenId) external onlyOwner {
        IERC721 token = IERC721(_tokenAddress);
        require(token.ownerOf(_tokenId) == address(this), "FinanceManager: The contract is not the owner of this token");
        token.safeTransferFrom(address(this), _recepient(), _tokenId);
    }

    /**
     * @dev Internal function to get the recipient address for withdrawals.
     * @return The address to which assets should be withdrawn.
     */
    function _recepient() internal view returns (address) {
        address recepient = owner();
        if (address(_proxyContract()) != address(0)) {
            recepient = _proxyContract().implementation();
        }
        return recepient;
    }
}


/*
 * An abstract contract extending the UtilityVotingAndOwnable contract to manage token transfers based on a voting mechanism.
 * Features include:
 * 1. Initiating a proposal for transferring a specified amount of tokens to a recipient.
 * 2. Voting on the proposal by eligible owners.
 * 3. Automatic execution of the transfer if at least 60% of the votes are in favor.
 * 4. Automatic cancellation of the proposal if over 40% of the votes are against it.
 * 5. Functionality to manually close a vote if it has been open for three or more days without resolution.
 * 6. Events to log voting actions and outcomes.
 * 7. A virtual internal function that must be overridden to actually perform the token transfer.
 */
abstract contract TokenManager is VoteUtility {

    // Suggested recipient address
    address internal _proposedTransferRecepient;
    // Offered number of tokens to send
    uint256 internal _proposedTransferAmount;
    // Structure for counting votes
    VoteResult internal _votesForTransfer;

    // Event about the fact of voting, parameters: voter, recipient, amount, vote
    event VotingForTransfer(address indexed voter, address recepient, uint256 amount, bool vote);
    // Event about the fact of making a decision on voting, parameters: voter, recipient, amount, vote, votesFor, votesAgainst
    event VotingTransferCompleted(address indexed voter, address recepient, uint256 amount, bool vote, uint votesFor, uint votesAgainst);
    // Event to close a poll that has expired
    event CloseVoteForTransfer(address indexed decisiveVote, uint votesFor, uint votesAgainst);

    // Voting start initiation, parameters: recipient, amount
    function initiateTransfer(address recepient, uint256 amount) public onlyOwner {
        require(amount != 0, "TokenManager: Incorrect amount");
        require(_proposedTransferAmount == 0, "TokenManager: voting is already activated");
        if (address(_proxyContract()) != address(0)) {
            require(!_proxyContract().isBlacklisted(recepient), "TokenManager: this address is blacklisted");
        }

        _proposedTransferRecepient = recepient;
        _proposedTransferAmount = amount;
        _votesForTransfer = VoteResult(new address[](0), new address[](0), block.timestamp);
        _voteForTransfer(true);
    }

    // Vote for transfer
    function voteForTransfer(bool vote) external onlyOwner {
        _voteForTransfer(vote);
    }

    // Votes must reach a 60% threshold to pass. If over 40% are downvotes, the measure fails.
    function _voteForTransfer(bool vote) internal hasNotVoted(_votesForTransfer) {
        require(_proposedTransferAmount != 0, "TokenManager: There is no active voting on this issue");

        (uint votestrue, uint votesfalse, uint256 _totalOwners) = _votes(_votesForTransfer, vote);

        emit VotingForTransfer(msg.sender, _proposedTransferRecepient, _proposedTransferAmount, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _transferFor(_proposedTransferRecepient, _proposedTransferAmount);
            _completionVotingTransfer(vote, votestrue, votesfalse);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _completionVotingTransfer(vote, votestrue, votesfalse);
        }
    }

    // Completion of voting
    function _completionVotingTransfer(bool vote, uint256 votestrue, uint256 votesfalse) internal {
         emit VotingTransferCompleted(msg.sender, _proposedTransferRecepient, _proposedTransferAmount, vote, votestrue, votesfalse);
        _completionVoting(_votesForTransfer);
        _proposedTransferRecepient = address(0);
        _proposedTransferAmount = 0;
    }

    // An abstract internal function for transferring tokens
    function _transferFor(address recepient, uint256 amount) internal virtual;

    // A function to close a vote on which a decision has not been made for three or more days
    function closeVoteForTransfer() public onlyOwner {
        require(_proposedTransferRecepient != address(0), "TokenManager: There is no open vote");
        emit CloseVoteForTransfer(msg.sender, _votesForTransfer.isTrue.length, _votesForTransfer.isFalse.length);
        _closeVote(_votesForTransfer);
        _proposedTransferRecepient = address(0);
        _proposedTransferAmount = 0;
    }

    // A function for obtaining information about the status of voting
    function getActiveForVoteTransfer() external view returns (address, uint256) {
        require(_proposedTransferRecepient != address(0), "TokenManager: re is no active voting");
        return (_proposedTransferRecepient, _proposedTransferAmount);
    }
}


/*
 * This abstract contract extends the UtilityVotingAndOwnable contract to facilitate governance of smart contract proxies.
 * Key features include:
 * 1. Initiating a proposal for setting a new proxy address.
 * 2. Voting on the proposed new proxy address by the proxy owners.
 * 3. Automatic update of the proxy address if a 70% threshold of affirmative votes is reached.
 * 4. Automatic cancellation of the proposal if over 30% of the votes are against it.
 * 5. Functionality to manually close an open vote that has been pending for more than three days without a conclusive decision.
 * 6. Events to log voting actions and outcomes for transparency and auditing purposes.
 * 7. Utility functions to check the status of the active vote and the validity of the proposed proxy address.
 */
abstract contract ProxyManager is VoteUtility {

    // A new smart contract proxy address is proposed
    address internal _proposedProxy;
    // Structure for counting votes
    VoteResult internal _votesForNewProxy;

    // Event about the fact of voting, parameters: voter, proposedProxy, vote
    event VotingForNewProxy(address indexed voter, address proposedProxy, bool vote);
    // Event about the fact of making a decision on voting, parameters: voter, proposedProxy, vote, votesFor, votesAgainst
    event VotingNewProxyCompleted(address indexed voter, address proposedProxy, bool vote, uint votesFor, uint votesAgainst);
    // Event to close a poll that has expired
    event CloseVoteForNewProxy(address indexed decisiveVote, address indexed votingObject, uint votesFor, uint votesAgainst);

    // Voting start initiation, parameters: proposedNewProxy
    function initiateNewProxy(address proposedNewProxy) public onlyOwner {
        require(!_isActiveForVoteNewProxy(), "ProxyManager: voting is already activated");
        require(_checkIProxyContract(proposedNewProxy), "ProxyManager: This address does not represent a contract that implements the IProxy interface.");

        _proposedProxy = proposedNewProxy;
        _votesForNewProxy = VoteResult(new address[](0), new address[](0), block.timestamp);
        _voteForNewProxy(true);
    }

    // Vote to change the owner of a smart contract
    function voteForNewProxy(bool vote) external onlyOwner {
        _voteForNewProxy(vote);
    }

    // Votes must reach a 70% threshold to pass. If over 30% are downvotes, the measure fails.
    function _voteForNewProxy(bool vote) internal hasNotVoted(_votesForNewProxy) {
        require(_isActiveForVoteNewProxy(), "ProxyManager: there are no votes at this address");

        (uint votestrue, uint votesfalse, uint256 _totalOwners) = _votes(_votesForNewProxy, vote);

        emit VotingForNewProxy(msg.sender, _proposedProxy, vote);

        if (votestrue * 100 >= _totalOwners * 70) {
            _setProxyContract(_proposedProxy);
            _completionVotingNewProxy(vote, votestrue, votesfalse);
        } else if (votesfalse * 100 > _totalOwners * 30) {
            _completionVotingNewProxy(vote, votestrue, votesfalse);
        }
    }
    
    // Completion of voting
    function _completionVotingNewProxy(bool vote, uint256 votestrue, uint256 votesfalse) internal {
        emit VotingNewProxyCompleted(msg.sender, _proposedProxy, vote, votestrue, votesfalse);
        _completionVoting(_votesForNewProxy);
        _proposedProxy = address(0);
    }

    // A function to close a vote on which a decision has not been made for three or more days
    function closeVoteForNewProxy() public onlyOwner {
        require(_proposedProxy != address(0), "ProxyManager: There is no open vote");
        emit CloseVoteForNewProxy(msg.sender, _proposedProxy, _votesForNewProxy.isTrue.length, _votesForNewProxy.isFalse.length);
        _closeVote(_votesForNewProxy);
        _proposedProxy = address(0);
    }

    // A function for obtaining information about the status of voting
    function getActiveForVoteNewProxy() external view returns (address) {
        require(_isActiveForVoteNewProxy(), "ProxyManager: re is no active voting");
        return _proposedProxy;
    }

    // Function to check if the proposed address is valid
    function _isActiveForVoteNewProxy() internal view returns (bool) {
        return _proposedProxy != address(0) && _proposedProxy !=  address(_proxyContract());
    }
}


/*
 * This abstract contract extends the UtilityVotingAndOwnable contract to manage the ownership of the smart contract.
 * Key features include:
 * 1. Initiating a proposal for changing the owner of the smart contract.
 * 2. Allowing current proxy owners to vote on the proposed new owner.
 * 3. Automatic update of the contract's owner if a 60% threshold of affirmative votes is reached.
 * 4. Automatic cancellation of the proposal if over 40% of the votes are against it.
 * 5. Functionality to manually close an open vote that has been pending for more than three days without a conclusive decision.
 * 6. Events to log voting actions and outcomes for transparency and auditing purposes.
 * 7. Utility functions to check the status of the active vote and the validity of the proposed new owner.
 * 8. Override of the standard 'transferOwnership' function to initiate the voting process, with additional checks against a blacklist and validation of the proposed owner.
 */
abstract contract OwnableManager is VoteUtility {

    // Proposed new owner
    address internal _proposedOwner;
    // Structure for counting votes
    VoteResult internal _votesForNewOwner;

    // Event about the fact of voting, parameters: voter, proposedOwner, vote
    event VotingForOwner(address indexed voter, address proposedOwner, bool vote);
    // Event about the fact of making a decision on voting, parameters: voter, proposedOwner, vote, votesFor, votesAgainst
    event VotingOwnerCompleted(address indexed voter, address proposedOwner, bool vote, uint votesFor, uint votesAgainst);
    // Event to close a poll that has expired
    event CloseVoteForNewOwner(address indexed decisiveVote, address indexed votingObject, uint votesFor, uint votesAgainst);

    // Overriding the transferOwnership function, which now triggers the start of a vote to change the owner of a smart contract
    function transferOwnership(address proposedOwner) public onlyOwner {
        require(!_isActiveForVoteOwner(), "OwnableManager: voting is already activated");
        if (address(_proxyContract()) != address(0)) {
            require(!_proxyContract().isBlacklisted(proposedOwner), "OwnableManager: this address is blacklisted");
            require(_isProxyOwner(proposedOwner), "OwnableManager: caller is not the proxy owner");
        }

        _proposedOwner = proposedOwner;
        _votesForNewOwner = VoteResult(new address[](0), new address[](0), block.timestamp);
        _voteForNewOwner(true);
    }

    // Vote For New Owner
    function voteForNewOwner(bool vote) external onlyOwner {
        _voteForNewOwner(vote);
    }

    // Votes must reach a 60% threshold to pass. If over 40% are downvotes, the measure fails.
    function _voteForNewOwner(bool vote) internal hasNotVoted(_votesForNewOwner) {
        require(_isActiveForVoteOwner(), "OwnableManager: there are no votes at this address");

        (uint votestrue, uint votesfalse, uint256 _totalOwners) = _votes(_votesForNewOwner, vote);

        emit VotingForOwner(msg.sender, _proposedOwner, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _transferOwnership(_proposedOwner);
            _completionVotingNewOwner(vote, votestrue, votesfalse);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _completionVotingNewOwner(vote, votestrue, votesfalse);
        }
    }
    
    // Completion of voting
    function _completionVotingNewOwner(bool vote, uint256 votestrue, uint256 votesfalse) internal {
        emit VotingOwnerCompleted(msg.sender, _proposedOwner, vote, votestrue, votesfalse);
        _completionVoting(_votesForNewOwner);
        _proposedOwner = address(0);
    }

    // A function to close a vote on which a decision has not been made for three or more days
    function closeVoteForNewOwner() public onlyOwner {
        require(_proposedOwner != address(0), "OwnableManager: There is no open vote");
        emit CloseVoteForNewOwner(msg.sender, _proposedOwner, _votesForNewOwner.isTrue.length, _votesForNewOwner.isFalse.length);
        _closeVote(_votesForNewOwner);
        _proposedOwner = address(0);
    }

    // Check if voting is enabled for new contract owner and their address.
    function getActiveForVoteOwner() external view returns (address) {
        require(_isActiveForVoteOwner(), "OwnableManager: re is no active voting");
        return _proposedOwner;
    }

    // Function to check if the proposed Owner address is valid
    function _isActiveForVoteOwner() internal view returns (bool) {
        return _proposedOwner != address(0) && _proposedOwner !=  owner();
    }
}


/*
 * This abstract contract extends the UtilityVotingAndOwnable contract to manage a whitelist of smart contract addresses.
 * Key features include:
 * 1. Initiating a proposal to allow or disallow a smart contract address.
 * 2. Allowing current proxy owners to vote on whether the proposed smart contract address should be whitelisted.
 * 3. Voting must reach a 60% threshold for the smart contract address to be whitelisted.
 * 4. Automatic failure of the proposal if over 40% of the votes are against it.
 * 5. Events to log the voting process and final decision for auditing and transparency.
 * 6. Functionality to manually close an open vote that has been pending for more than three days without a conclusive decision.
 * 7. Utility functions to check if the proposed contract address is valid, if there's an active vote, and if an address is whitelisted.
 * 8. Checks that the proposed smart contract implements the IANHReceiver interface.
 */
abstract contract WhiteListManager is VoteUtility {

    // Whitelist
    mapping(address => bool) internal _whiteList;
    // A new smart contract proxy address is proposed
    address internal _proposedContract;
    // Structure for counting votes
    VoteResult internal _votesForAllowContract;

    // Event about the fact of voting, parameters: voter, proposedProxy, vote
    event VotingForAllowContract(address indexed voter, address proposedProxy, bool vote);
    // Event about the fact of making a decision on voting, parameters: voter, proposedProxy, vote, votesFor, votesAgainst
    event VotingAllowContractCompleted(address indexed voter, address proposedProxy, bool vote, uint votesFor, uint votesAgainst);
    // Event to close a poll that has expired
    event CloseVoteForAllowContract(address indexed decisiveVote, address indexed votingObject, uint votesFor, uint votesAgainst);

    // Voting start initiation, parameters: proposedNewProxy
    function initiateAllowContract(address proposedContract) public onlyOwner {
        require(!_isActiveForVoteAllowContract(), "WhiteListManager: voting is already activated");
        require(_or1820RegistryReturnIERC20Received(proposedContract) ||
            IERC165(proposedContract).supportsInterface(type(IERC20Receiver).interfaceId), 
            "WhiteListManager: This address does not represent a contract that implements the IANHReceiver interface.");

        _proposedContract = proposedContract;
        _votesForAllowContract = VoteResult(new address[](0), new address[](0), block.timestamp);
        _voteForAllowContract(true);
    }

    function _or1820RegistryReturnIERC20Received(address contractAddress) internal view virtual returns (bool);

    // Vote
    function voteForAllowContract(bool vote) external onlyOwner {
        _voteForAllowContract(vote);
    }

    // Votes must reach a 60% threshold to pass. If over 40% are downvotes, the measure fails.
    function _voteForAllowContract(bool vote) internal hasNotVoted(_votesForAllowContract) {
        require(_isActiveForVoteAllowContract(), "WhiteListManager: there are no votes at this address");

        (uint votestrue, uint votesfalse, uint256 _totalOwners) = _votes(_votesForAllowContract, vote);

        emit VotingForAllowContract(msg.sender, _proposedContract, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _whiteList[_proposedContract] = !_whiteList[_proposedContract];
            _completionVotingAllowContract(vote, votestrue, votesfalse);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _completionVotingAllowContract(vote, votestrue, votesfalse);
        }
    }
    
    // Completion of voting
    function _completionVotingAllowContract(bool vote, uint256 votestrue, uint256 votesfalse) internal {
        emit VotingAllowContractCompleted(msg.sender, _proposedContract, vote, votestrue, votesfalse);
        _completionVoting(_votesForAllowContract);
        _proposedContract = address(0);
    }

    // A function to close a vote on which a decision has not been made for three or more days
    function closeVoteForAllowContract() public onlyOwner {
        require(_proposedContract != address(0), "WhiteListManager: There is no open vote");
        emit CloseVoteForAllowContract(msg.sender, _proposedContract, _votesForAllowContract.isTrue.length, _votesForAllowContract.isFalse.length);
        _closeVote(_votesForAllowContract);
        _proposedContract = address(0);
    }

    // A function for obtaining information about the status of voting
    function getActiveForVoteAllowContract() external view returns (address, bool) {
        require(_isActiveForVoteAllowContract(), "WhiteListManager: re is no active voting");
        return (_proposedContract, !_whiteList[_proposedContract]);
    }

    // Is the address whitelisted
    function isinWhitelist(address contractAddress) external view returns (bool) {
        return _whiteList[contractAddress];
    }

    // Function to check if the proposed address is valid
    function _isActiveForVoteAllowContract() internal view returns (bool) {
        return _proposedContract != address(0);
    }
}


// Declares an abstract contract ERC165 that implements the IERC165 interface
abstract contract ERC165 is IERC165 {

    // Internal mapping to store supported interfaces
    mapping(bytes4 => bool) internal supportedInterfaces;

    // Constructor to initialize the mapping of supported interfaces
    constructor() {
        // 0x01ffc9a7 is the interface identifier for ERC165 according to the standard
        supportedInterfaces[0x01ffc9a7] = true;
    }

    // Implements the supportsInterface method from the IERC165 interface
    // The function checks if the contract supports the given interface
    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return supportedInterfaces[interfaceId];
    }
}

/*
 * IERC20Receiver Interface:
 * - Purpose: To handle the receiving of ERC-20 tokens from another smart contract.
 * - Key Method: 
 *   - `onERC20Received`: This is called when tokens are transferred to a smart contract implementing this interface.
 *                        It allows for custom logic upon receiving tokens.
 */
interface IERC20Receiver {
    // Function that is triggered when ERC20 (ANH) tokens are received.
    function onERC20Received(address _from, address _who, uint256 _amount) external returns (bytes4);
}

/*
 * ERC20Receiver Contract:
 * - Inherits From: IERC20Receiver, ERC20
 * - Purpose: To handle incoming ERC-20 tokens and trigger custom logic upon receipt.
 * - Special Features:
 *   - Verifies the compliance of receiving contracts with the IERC20Receiver interface.
 *   - Uses the ERC1820 Registry to identify contracts that implement the IERC20Receiver interface.
 *   - Safely calls `onERC20Received` on the receiving contract and logs any exceptions.
 *   - Extends the standard ERC20 `_afterTokenTransfer` function to incorporate custom logic.
 * 
 * - Key Methods:
 *   - `_onERC20Received`: Internal function to verify and trigger `onERC20Received` on receiving contracts.
 *   - `_afterTokenTransfer`: Overridden from ERC20 to add additional behavior upon token transfer.
 *   - `onERC20Received`: Implements the IERC20Receiver interface, allowing the contract to handle incoming tokens.
 * 
 * - Events:
 *   - TokensReceivedProcessed: Logs successful processing of incoming tokens by receiving contracts.
 *   - ExceptionInfo: Logs exceptions during the execution of `onERC20Received` on receiving contracts.
 *   - ReturnOfThisToken: Logs when tokens are received from this contract itself.
 * 
 */
abstract contract ERC20Receiver is IERC20Receiver, ERC20Burnable, ERC165 {

    // The magic identifier for the ability in the external contract to cancel the token acquisition transaction
    bytes4 internal ERC20ReceivedMagic;

    IERC1820Registry constant internal erc1820Registry = IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

    // An event to track from which address the tokens were transferred, who transferred, to which address and the number of tokens
    event ChallengeIERC20Receiver(address indexed from, address indexed who, address indexed token, uint256 amount);
    // An event to log the return of Anhydrite tokens to this smart contract
    event ReturnOfMainToken(address indexed from, address indexed who, address indexed thisToken, uint256 amount);
    // An event about an exception that occurred during the execution of an external contract 
    event ExceptionInfo(address indexed to, string exception);


    constructor() {
        supportedInterfaces[type(IERC20).interfaceId] = true;
        supportedInterfaces[type(IERC20Receiver).interfaceId] = true;

        ERC20ReceivedMagic = IERC20Receiver(address(this)).onERC20Received.selector;
        erc1820Registry.setInterfaceImplementer(address(this), keccak256("ERC20Token"), address(this));
        erc1820Registry.setInterfaceImplementer(address(this), keccak256("IERC20Receiver"), address(this));
    }

    /*
     * Overridden Function: onERC20Received
     * - Purpose: Implements the onERC20Received function from the IERC20Receiver interface to handle incoming ERC-20 tokens.
     * - Arguments:
     *   - _from: The sender of the ERC-20 tokens.
     *   - _who: Indicates the original sender for forwarded tokens (useful in case of proxy contracts).
     *   - _amount: The amount of tokens being sent.
     * 
     * - Behavior:
     *   1. If the message sender is this contract itself, it emits a ReturnOfAnhydrite event and returns the method selector for onERC20Received, effectively acknowledging receipt.
     *   2. If the message sender is not this contract, it returns a different bytes4 identifier, which signifies the tokens were not properly processed as per IERC20Receiver standards.
     * 
     * - Returns:
     *   - The function returns a "magic" identifier (bytes4) that confirms the execution of the onERC20Received function.
     *
     * - Events:
     *   - ReturnOfMainToken: Emitted when tokens are received from this contract itself.
     *   - DepositERC20: Emitted when other tokens of the EPC-20 standard are received
     */
    function onERC20Received(address _from, address _who, uint256 _amount) external override returns (bytes4) {
        bytes4 fakeID = bytes4(keccak256("anything_else"));
        bytes4 validID = ERC20ReceivedMagic;
        bytes4 returnValue = fakeID;  // Default value
        if (msg.sender.code.length > 0) {
            if (msg.sender == address(this)) {
                emit ReturnOfMainToken(_from, _who, address(this), _amount);
                returnValue = validID;
            } else {
                try IERC20(msg.sender).balanceOf(address(this)) returns (uint256 balance) {
                    if (balance >= _amount) {
                        emit ChallengeIERC20Receiver(_from, _who, msg.sender, _amount);
                        returnValue = validID;
                    }
                } catch {
                    // No need to change returnValue, it's already set to fakeID 
                }
            }
        }
        return returnValue;
    }

    // An abstract function for implementing a whitelist to handle trusted contracts with special logic.
    // If this is not required, implement a simple function that always returns false
    function _checkWhitelist(address checked) internal view virtual returns (bool);

    /*
     * Private Function: _onERC20Received
     * - Purpose: Handles the receipt of ERC20 tokens, checking if the receiver implements IERC20Receiver or is whitelisted.
     * - Arguments:
     *   - _from: The sender's address of the ERC-20 tokens.
     *   - _to: The recipient's address of the ERC-20 tokens.
     *   - _amount: The quantity of tokens to be transferred.
     * 
     * - Behavior:
     *   1. Checks if `_to` is a contract by examining the length of its bytecode.
     *   2. If `_to` is whitelisted, it calls the `onERC20Received` method on `_to`, requiring a magic value to be returned.
     *   3. Alternatively, if `_to` is an IERC20Receiver according to the ERC1820 registry, it calls the `_difficultChallenge` method.
     *   4. If none of these conditions are met, the function simply exits, effectively treating `_to` as a regular address.
     */
    function _onERC20Received(address _from, address _to, uint256 _amount) private {
        if (_to.code.length > 0) {
            if (_checkWhitelist(_to)) {
	            bytes4 retval = IERC20Receiver(_to).onERC20Received(_from, msg.sender, _amount);
                require(retval == ERC20ReceivedMagic, "ERC20Receiver: An invalid magic ID was returned");
            } else if (_or1820RegistryReturnIERC20Received(_to)) {
	            _difficultChallenge(_from, _to, _amount);
            }
        }
	}

    /*
     * Internal Function: _difficultChallenge
     * - Purpose: Calls the `onERC20Received` function of the receiving contract and logs exceptions if they occur.
     * - Arguments:
     *   - _from: The origin address of the ERC-20 tokens.
     *   - _to: The destination address of the ERC-20 tokens.
     *   - _amount: The quantity of tokens being transferred.
     *   
     * - Behavior:
     *   1. A try-catch block attempts to call the `onERC20Received` function on the receiving contract `_to`.
     *   2. If the call succeeds, the returned magic value is checked.
     *   3. If the call fails, an exception is caught and the reason is emitted in an ExceptionInfo event.
     */
    function _difficultChallenge(address _from, address _to, uint256 _amount) private {
        bytes4 retval;
        bool callSuccess;
        try IERC20Receiver(_to).onERC20Received(_from, msg.sender, _amount) returns (bytes4 _retval) {
	        retval = _retval;
            callSuccess = true;
	    } catch Error(string memory reason) {
            emit ExceptionInfo(_to, reason);
	    } catch (bytes memory lowLevelData) {
            string memory infoError = "Another error";
            if (lowLevelData.length > 0) {
                infoError = string(lowLevelData);
            }
            emit ExceptionInfo(_to, infoError);
	    }
        if (callSuccess) {
            require(retval == ERC20ReceivedMagic, "ERC20Receiver: An invalid magic ID was returned");
        }
    }

    /*
     * Internal View Function: _or1820RegistryReturnIERC20Received
     * - Purpose: Checks if the contract at `contractAddress` implements the IERC20Receiver interface according to the ERC1820 registry.
     * - Arguments:
     *   - contractAddress: The address of the contract to check.
     * 
     * - Returns: 
     *   - A boolean indicating whether the contract implements IERC20Receiver according to the ERC1820 registry.
     */
    function _or1820RegistryReturnIERC20Received(address contractAddress) internal view virtual returns (bool) {
        return erc1820Registry.getInterfaceImplementer(contractAddress, keccak256("IERC20Receiver")) == contractAddress;
    }

    /*
     * Public View Function: or1820RegistryReturnsIERC20Received
     * - Purpose: External interface for checking if a contract implements the IERC20Receiver interface via the ERC1820 registry.
     * - Arguments:
     *   - contractAddress: The address of the contract to check.
     * 
     * - Returns:
     *   - A boolean indicating the ERC1820 compliance of the contract.
     */
    function or1820RegistryReturnsIERC20Received(address contractAddress) external view returns (bool) {
        return _or1820RegistryReturnIERC20Received(contractAddress);
    }

    /*
     * Public View Function: checkERC20Received
     * - Purpose: Checks and returns the whitelist and ERC1820 registry status of a contract.
     * - Arguments:
     *   - contractAddress: The address of the contract to check.
     * 
     * - Returns:
     *   - Two strings representing the whitelist and ERC1820 status ("WhiteList"/"false" and "1820Registry"/"false").
     */
    function checkERC20Received(address contractAddress) external view returns (string memory, string memory) {
        string memory checkWhiteList = _checkWhitelist(contractAddress) ? "WhiteList" : "false";
        string memory check1820Registry = erc1820Registry.getInterfaceImplementer(
            contractAddress, keccak256("IERC20Receiver")) == contractAddress ? "1820Registry" : "false";
        return (checkWhiteList, check1820Registry);
    }


    /*
     * Overridden Function: _afterTokenTransfer
     * - Purpose: Extends the original _afterTokenTransfer function by additionally invoking _onERC20Received when recepient are not the zero address.
     * - Arguments:
     *   - from: The sender's address.
     *   - to: The recipient's address.
     *   - amount: The amount of tokens being transferred.
     *
     * - Behavior:
     *   1. If the recipient's address (`to`) is not the zero address, this function calls the internal method _onERC20Received.
     *
     */
    function _afterTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if(to != address(0)) {
            _onERC20Received(from, to, amount);
        }
    }
}
/*
 * IERC1820Registry defines the interface for the ERC1820 Registry contract,
 * which allows contracts and addresses to declare which interface they implement
 * and which smart contract is responsible for its implementation.
 */
interface IERC1820Registry {

    // Allows `account` to specify `implementer` as the entity that implements
    // a particular interface identified by `interfaceHash`.
    // This can only be called by the `account` itself.
    function setInterfaceImplementer(address account, bytes32 interfaceHash, address implementer) external;

    // Retrieves the address of the contract that implements a specific interface
    // identified by `interfaceHash` for `account`.
    function getInterfaceImplementer(address account, bytes32 interfaceHash) external view returns (address);
}


/*
 * Anhydrite Contract:
 * - Inherits From: FinanceManager, TokenManager, ProxyManager, OwnableManager, ERC20, ERC20Burnable, ERC20Receiver.
 * - Purpose: Provides advanced features to a standard ERC-20 token including token minting, burning, and ownership voting.
 * - Special Features:
 *   - Sets a maximum supply limit of 360 million tokens.
 * - Key Methods:
 *   - `getMaxSupply`: Returns the maximum allowed supply of tokens.
 *   - `transferForProxy`: Only allows a proxy smart contract to initiate token transfers.
 *   - `_transferFor`: Checks and performs token transfers, and mints new tokens if necessary, but not exceeding max supply.
 *   - `_mint`: Enforces the max supply limit when minting tokens.
 */
contract Anhydrite is ERC20Receiver, FinanceManager, TokenManager, ProxyManager, OwnableManager, WhiteListManager {

    // Sets the maximum allowed supply of tokens is 360 million
    uint256 private constant MAX_SUPPLY = 360000000 * 10 ** 18;

    constructor() ERC20("Anhydrite", "ANH") {
        _mint(address(this), 70000000 * 10 ** decimals());
        _whiteList[address(this)] = true;
        erc1820Registry.setInterfaceImplementer(address(this), keccak256("IANH"), address(this));
   }

    // Returns the maximum token supply allowed
    function getMaxSupply() public pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // Sending tokens on request from the smart contract proxy to its address
    function transferForProxy(uint256 amount) public {
        require(address(_proxyContract()) != address(0), "Anhydrite: The proxy contract has not yet been established");
        address proxy = address(_proxyContract());
        require(msg.sender == proxy, "Anhydrite: Only a proxy smart contract can activate this feature");
        _transferFor(proxy, amount);
    }

    // Implemented _transferFor function checks token presence, sends to recipient, and mints new tokens if necessary, but not exceeding max supply.
    function _transferFor(address recepient, uint256 amount) internal override {
        if (balanceOf(address(this)) >= amount) {
            _transfer(address(this), recepient, amount);
        } else if (totalSupply() + amount <= MAX_SUPPLY && recepient != address(0)) {
            _mint(recepient, amount);
        } else {
            revert("Anhydrite: Cannot transfer or mint the requested amount");
        }
    }

    /*
     * Internal function to check if an address is on the whitelist.
     * This function overrides a function defined in a parent contract (as indicated by the `override` keyword).
     * It returns a boolean value indicating the whitelist status of the given address `checked`.
     */
    function _checkWhitelist(address checked) internal view override returns (bool) {
        return _whiteList[checked];
    }

    /*
     * Overridden Function: _mint
     * Extends the original _mint function from the ERC20 contract to include a maximum supply limit.
     */
    function _mint(address account, uint256 amount) internal virtual override {
        require(totalSupply() + amount <= MAX_SUPPLY, "Anhydrite: MAX_SUPPLY limit reached");
        super._mint(account, amount);
    }

    /*
     * Internal function that determines whether the given `contractAddress` should return the standard
     * `IERC20Received` response or follow the ERC1820 registry behavior.
     * This function overrides functions from both the `WhiteListManager` and `ERC20Receiver` parent contracts
     * as indicated by the `override(WhiteListManager, ERC20Receiver)` keyword.
     * It returns a boolean value that dictates the behavior for handling incoming ERC20 tokens.
     */
    function _or1820RegistryReturnIERC20Received(address contractAddress) internal override(WhiteListManager, ERC20Receiver) 
      view returns (bool) {
        return ERC20Receiver._or1820RegistryReturnIERC20Received(contractAddress);
    }
}