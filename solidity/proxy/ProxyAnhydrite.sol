// SPDX-License-Identifier: All rights reserved
// Anything related to the Anhydrite project, except for the OpenZeppelin library code, is protected.
// Copying, modifying, or using without proper attribution to the Anhydrite project and a link to https://anh.ink is strictly prohibited.

pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";

/// @custom:security-contact support@anh.ink


/*
* A set of interfaces and smart contracts that implement a proxy contract, 
* the main purpose of which is to delegate calls to a global smart contract.
*
* And also the implementation of the system of owners, where all decisions are made by voting.
*/

interface IProxy {
    
    function getToken() external view returns (IERC20);
    function getImplementation() external view returns (address);
    function isStopped() external view returns (bool);
    function getTotalOwners() external view returns (uint256);
    function isProxyOwner(address tokenAddress) external view returns (bool);
    function isOwner(address account) external view returns (bool);
    function getBalanceOwner(address owner) external view returns (uint256);
    function getTokensNeededForOwnership() external view returns (uint256);
    function isBlacklisted(address account) external view returns (bool);
    function depositTokens(uint256 amount) external;
    function voluntarilyExit() external;
    function withdrawExcessTokens() external;
    function rescueTokens(address tokenAddress) external;

    event VoluntarilyExit(address indexed votingSubject, uint returTokens);
}

/*
* The abstract proxy smart contract that implements the IProxy interface,
* the main goal here is to delegate calls to the global smart contract,
* to set the project's main token.
*
* In addition, the possibility of depositing tokens by owners to their account in a smart contract,
* withdrawing excess tokens, as well as voluntary exit from owners is realized here.
* There is also an opportunity to get information about the global token, about the owners,
* their deposits, to find out whether the address is among the owners, as well as whether it has the right to vote.
*/
abstract contract Proxy is IProxy, IERC721Receiver {

    struct VoteResult {
        address[] isTrue;
        address[] isFalse;
        uint256 timestamp;
    }

    IERC20 internal immutable _token;
    address internal _implementation;
    bool internal _stopped = false;

    uint256 internal _totalOwners;
    mapping(address => bool) internal _owners;
    mapping(address => uint256) internal _balanceOwner;
    
    uint256 internal _tokensNeededForOwnership;

    mapping(address => uint256) internal _initiateOwners;
    mapping(address => bool) internal _isOwnerVotedOut;
    mapping(address => bool) internal _blackList;

    address internal _proposedImplementation;
    VoteResult internal _votesForNewImplementation;

    bool internal _proposedStopped = false;
    VoteResult internal _votesForStopped;

    uint256 internal _proposedTokensNeeded;
    VoteResult internal _votesForTokensNeeded;

    address internal _proposedOwner;
    VoteResult internal _votesForNewOwner;
    
    address internal _proposedRemoveOwner;
    VoteResult internal _votesForRemoveOwner;
    
    constructor() {
        _implementation = address(0);
        _owners[msg.sender] = true;
        _totalOwners++;
        _token = IERC20(0x578b350455932aC3d0e7ce5d7fa62d7785872221);
        _tokensNeededForOwnership = 1 * 10 **18;
    }

    // Returns an ERC20 standard token, which is the main token of the project
    function getToken() external override view returns (IERC20) {
        return _token;
    }

    // A function for obtaining the address of a global smart contract
    function getImplementation() external override view returns (address) {
        return _implementation;
    }

    // A function to obtain information about whether the basic functions of the smart contract are stopped
    function isStopped() external override view returns (bool) {
        return _stopped;
    }

    // Function for obtaining information about the total number of owners
    function getTotalOwners() external override view returns (uint256) {
        return _totalOwners;
    }

    // The function for obtaining information whether the address is among the owners and whether it has the right to vote
    function isProxyOwner(address tokenAddress) external override view returns (bool) {
        return _owners[tokenAddress] 
        && !_isOwnerVotedOut[tokenAddress]
        && _balanceOwner[tokenAddress] >= _tokensNeededForOwnership;
    }

    // Function for obtaining information whether the address is among the owners
    function isOwner(address account) external override view returns (bool) {
        return _owners[account];
    }

    // Function for obtaining information about the balance of the owner
    function getBalanceOwner(address owner) external override view returns (uint256) {
        return _balanceOwner[owner];
    }

    // A function to obtain information about the number of Master Tokens required on the owner's balance to be eligible to vote
    function getTokensNeededForOwnership() external override view returns (uint256) {
        return _tokensNeededForOwnership;
    }

    /*
    * 
    */
    function isBlacklisted(address account) external override view returns (bool) {
        return _blackList[account];
    }

    // Function for obtaining information about whether the address is in the black list
    function depositTokens(uint256 amount) external override onlyOwner {
        require(amount > 0, "Invalid amount");
        require(_token.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        _balanceOwner[msg.sender] += amount;
    }

    /*
    * A function for voluntary resignation of the owner from his position.
    * At the same time, his entire deposit is returned to his balance.
    */
    function voluntarilyExit() external override onlyOwner {
        require(!_isOwnerVotedOut[msg.sender], "You have been voted out");
        
        uint256 balance = _balanceOwner[msg.sender];
        if (balance > 0) {

            _balanceOwner[msg.sender] = 0;

            if(_token.balanceOf(address(this)) >= balance) {
                require(_token.transfer(msg.sender, balance), "Transfer failed");
            } else {
                IAnhydriteGlobal implementation = IAnhydriteGlobal(_implementation);
                require(implementation.getTokens(msg.sender, balance), "Execution failed");
            }
        }

        _owners[msg.sender] = false;
        _totalOwners--;

        emit VoluntarilyExit(msg.sender, balance);
    }
    
    // A function for the owner to withdraw excess tokens from his deposit
    function withdrawExcessTokens() external override onlyOwner {
        require(!_isOwnerVotedOut[msg.sender], "You have been voted out");
        uint256 ownerBalance = _balanceOwner[msg.sender];
        uint256 excess = 0;

        if (ownerBalance > _tokensNeededForOwnership) {
            excess = ownerBalance - _tokensNeededForOwnership;

            _balanceOwner[msg.sender] -= excess;

            if(_token.balanceOf(address(this)) >= excess) {
                require(_token.transfer(msg.sender, excess), "Transfer failed");
            } else {
                IAnhydriteGlobal implementation = IAnhydriteGlobal(_implementation);
                require(implementation.getTokens(msg.sender, excess), "Execution failed");
            }
            
        }
    }

    /*
    * Function to transfer tokens from the balance of the proxy smart contract to the balance of the global smart contract.
    * At the same time, it is impossible to transfer the global token
    */
    function rescueTokens(address tokenAddress) external override onlyOwner {
        require(tokenAddress != address(_token), "Cannot rescue the main token");
    
        IERC20 rescueToken = IERC20(tokenAddress);
        uint256 balance = rescueToken.balanceOf(address(this));
    
        require(balance > 0, "No tokens to rescue");
    
        require(rescueToken.transfer(_implementation, balance), "Transfer failed");
    }


    // Internal functions and modifiers
    
    function _hasOwnerVoted(VoteResult memory addresses, address targetAddress) internal pure returns (bool) {
        for (uint256 i = 0; i < addresses.isTrue.length; i++) {
            if (addresses.isTrue[i] == targetAddress) {
                return true;
            }
        }
        for (uint256 i = 0; i < addresses.isFalse.length; i++) {
            if (addresses.isFalse[i] == targetAddress) {
                return true;
            }
        }
        return false;
    }

    modifier canClose(address addresess, uint256 timestamp) {
        require(addresess != address(0), "There is no open vote");
        require(block.timestamp >= timestamp + 3 days, "Voting is still open");
        _;
    }

    modifier canYouVote(VoteResult memory result) {
        require(!_hasOwnerVoted(result, msg.sender), "Already voted");
        require(_balanceOwner[msg.sender] >= _tokensNeededForOwnership, "Insufficient tokens in staking balance");
        _;
    }

    modifier onlyOwner() {
        require(_owners[msg.sender], "Not an owner");
        require(!_isOwnerVotedOut[msg.sender], "This owner is being voted out");
        _;
    }

    // A function for delegating calls to a global smart contract

    function _delegate() internal virtual {
        require(!_stopped, "Contract is currently _stopped.");
        address _impl = _implementation;
        require(_impl != address(0), "Implementation == address(0)");

        assembly {
            calldatacopy(0, 0, calldatasize())
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    function _fallback() internal virtual {
        _delegate();
    }

    fallback() external payable virtual {
        _fallback();
    }

    receive() external payable {
        Address.sendValue(payable(address(_implementation)), msg.value);
    }

    function onERC721Received(address, address, uint256 tokenId, bytes calldata) external override returns (bytes4) {
        IERC721(msg.sender).safeTransferFrom(address(this), _implementation, tokenId);
        return this.onERC721Received.selector;
    }

}

/*
* Implementation of voting functions
*/
interface IVotes {
    function getVoteForNewTokensNeeded() external view returns (uint256, uint256, uint256, uint256);
    function getVoteForNewImplementationStatus() external view returns (address, uint256, uint256, uint256);
    function getVoteForNewOwnerStatus() external view returns (address, uint256, uint256, uint256);
    function getVoteForRemoveOwnerStatus() external view returns (address, uint256, uint256, uint256);
    function getVoteForStopped() external view returns (bool, uint256, uint256, uint256);
 
    function startVotingForStopped(bool _proposed) external;
    function voteForStopped(bool vote) external;
    function startVotingForNeededForOwnership(uint256 _proposed) external;
    function voteForNeededForOwnership(bool vote) external;
    function startVotingForNewImplementation(address _proposed) external;
    function voteForNewImplementation(bool vote) external;
    function initiateOwnershipRequest() external;
    function voteForNewOwner(address _owner, bool vote) external;
    function startVotingForRemoveOwner(address _proposed) external;
    function voteForRemoveOwner(bool vote) external;

    function closeVoteForStopped() external;
    function closeVoteForTokensNeeded() external;
    function closeVoteForNewImplementation() external;
    function closeVoteForNewOwner() external;
    function closeVoteForRemoveOwner() external;

    event VotingForStopped(address indexed addressVoter, bool indexed vote);
    event VotingCompletedForStopped(address indexed decisiveVote, bool indexed result, uint votesFor, uint votesAgainst);
    event CloseVoteForStopped(address indexed decisiveVote, uint votesFor, uint votesAgainst);

    event VotingForTokensNeeded(address indexed addressVoter, bool indexed vote);
    event VotingCompletedForTokensNeeded(address indexed decisiveVote, bool indexed result, uint votesFor, uint votesAgainst);
    event CloseVoteForTokensNeeded(address indexed decisiveVote, uint votesFor, uint votesAgainst);

    event VotingForNewImplementation(address indexed addressVoter, bool indexed vote);
    event VotingCompletedForNewImplementation(address indexed decisiveVote, bool indexed result, uint votesFor, uint votesAgainst);
    event CloseVoteForNewImplementation(address indexed decisiveVote, uint votesFor, uint votesAgainst);

    event VotingForNewOwner(address indexed addressVoter, address indexed votingObject, bool indexed vote);
    event VotingCompletedForNewOwner(address indexed decisiveVote, address indexed votingObject, bool indexed result, uint votesFor, uint votesAgainst);
    event CloseVoteForNewOwner(address indexed decisiveVote, address indexed votingObject, uint votesFor, uint votesAgainst);

    event VotingForRemoveOwner(address indexed addressVoter, address indexed votingObject, bool indexed vote);
    event VotingCompletedForRemoveOwner(address indexed decisiveVote, address indexed votingObject, bool indexed result, uint votesFor, uint votesAgainst);
    event CloseVoteForRemoveOwner(address indexed decisiveVote, address indexed votingObject, uint votesFor, uint votesAgainst);

    event InitiateOwnership(address indexed subject, bool indexed result);
}

/*
* AnhydriteProxy contract that implements the functions of the IVotes interface and also
* emulates all the functions and variables of the Proxy abstract smart contract.
*
* Implemented functions for obtaining information about active votes,
* voting functions and closing voting functions if the decision was not made.
*/
contract AnhydriteProxy is IVotes, Proxy {
    

    // Function to get the status of voting for new Tokens Needed
    function getVoteForNewTokensNeeded() public view returns (uint256, uint256, uint256, uint256) {
        return (
            _proposedTokensNeeded, 
            _votesForNewOwner.isTrue.length, 
            _votesForNewOwner.isFalse.length, 
            _votesForNewOwner.timestamp
        );
    }

    // Function to get the status of voting for new implementation
    function getVoteForNewImplementationStatus() public view returns (address, uint256, uint256, uint256) {
        return _getVote(_votesForNewImplementation, _proposedImplementation);
    }

    // Function to get the status of voting for new owner
    function getVoteForNewOwnerStatus() public view returns (address, uint256, uint256, uint256) {
        return _getVote(_votesForNewOwner, _proposedOwner);
    }

    // Function to get the status of voting for remove owner
    function getVoteForRemoveOwnerStatus() public view returns (address, uint256, uint256, uint256) {
        return _getVote(_votesForRemoveOwner, _proposedRemoveOwner);
    }

    // Function to get the status of voting for Stopped
    function getVoteForStopped() public view returns (bool, uint256, uint256, uint256) {
            return (
            _proposedStopped != _stopped,
            _votesForStopped.isTrue.length, 
            _votesForStopped.isFalse.length, 
            _votesForStopped.timestamp
        );
    }

    function startVotingForStopped(bool _proposed) public onlyOwner canYouVote(_votesForStopped) {
        require(_stopped != _proposed, "Votes: This vote will not change the Stop status");
        require(_proposed != _proposedStopped, "Votes: Voting has already started");
        _proposedStopped = _proposed;
        _votesForStopped.timestamp = block.timestamp;
        _voteForStopped(true);
    }

    // The function of voting for stopping and resuming the work of a smart contract
    function voteForStopped(bool vote) public onlyOwner canYouVote(_votesForStopped) {
        _voteForStopped(vote);
    }

    function _voteForStopped(bool vote) internal {
        require(_stopped != _proposedStopped, "Votes: There is no active voting on this issue");

        (uint votestrue, uint votesfalse) = _votes(_votesForStopped, vote);

        emit VotingForStopped(msg.sender, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _stopped = _proposedStopped;
            _resetVote(_votesForStopped);
            emit VotingCompletedForStopped(msg.sender, true, votestrue, votesfalse);
            
       } else if (votesfalse * 100 > _totalOwners * 40) {
            _resetVote(_votesForStopped);
            emit VotingCompletedForStopped(msg.sender, false, votestrue, votesfalse);
            _proposedStopped = !_proposedStopped;
        }
    }

    function startVotingForNeededForOwnership(uint256 _proposed) public onlyOwner canYouVote(_votesForStopped) {
        require(_proposed != 0, "Votes: The supply of need for ownership tokens cannot be zero");
        require(_tokensNeededForOwnership != _proposed, "Votes: This vote will not change the need for ownership tokens");
        require(_proposedTokensNeeded == 0, "Votes: Voting has already started");
        _proposedTokensNeeded = _proposed;
        _votesForTokensNeeded.timestamp = block.timestamp;
        _voteForNeededForOwnership(true);
    }

    // Voting function for changing the number of tokens on the balance required for the right to vote
    function voteForNeededForOwnership(bool vote) public onlyOwner canYouVote(_votesForTokensNeeded) {
        _voteForNeededForOwnership(vote);
    }

    // Voting function for changing the number of tokens on the balance required for the right to vote
    function _voteForNeededForOwnership(bool vote) internal {
        require(_proposedTokensNeeded != 0, "Votes: There is no active voting on this issue");

        (uint votestrue, uint votesfalse) = _votes(_votesForTokensNeeded, vote);

        emit VotingForTokensNeeded(msg.sender, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _tokensNeededForOwnership = _proposedTokensNeeded;
            emit VotingCompletedForTokensNeeded(msg.sender, vote, votestrue, votesfalse);
            _resetVote(_votesForTokensNeeded);
            _proposedTokensNeeded = 0;
       } else if (votesfalse * 100 > _totalOwners * 40) {
            emit VotingCompletedForTokensNeeded(msg.sender, vote, votestrue, votesfalse);
            _resetVote(_votesForTokensNeeded);
            _proposedTokensNeeded = 0;
        }
    }

    function startVotingForNewImplementation(address _proposed) public onlyOwner canYouVote(_votesForStopped) {
        require(_proposed != address(0), "Votes: Cannot set null address");
        require(_implementation != _proposed, "Votes: This vote will not change the implementation address");
        require(_proposedImplementation == address(0), "Votes: Voting has already started");
        _proposedImplementation = _proposed;
        _votesForNewImplementation.timestamp = block.timestamp;
        _voteForNewImplementation(true);
    }

    // Global smart contract address change voting function
    function voteForNewImplementation(bool vote) public onlyOwner canYouVote(_votesForNewImplementation) {
        _voteForNewImplementation(vote);
    }
    function _voteForNewImplementation(bool vote) internal {
        require(_proposedImplementation != address(0), "Votes: There is no active voting on this issue");

        (uint votestrue, uint votesfalse) = _votes(_votesForNewImplementation, vote);

        emit VotingForNewImplementation(msg.sender, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _implementation = _proposedImplementation;
            _resetVote(_votesForNewImplementation);
            emit VotingCompletedForNewImplementation(msg.sender, vote, votestrue, votesfalse);
            _proposedImplementation = address(0);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _resetVote(_votesForNewImplementation);
            emit VotingCompletedForNewImplementation(msg.sender, vote, votestrue, votesfalse);
            _proposedImplementation = address(0);
        }
    }

    // Function for submitting an application for admission to owners
    function initiateOwnershipRequest() public {
        require(!_owners[msg.sender], "Votes: Already an owner");
        require(!_blackList[msg.sender], "Votes: This address is blacklisted");
        require(block.timestamp >= _initiateOwners[msg.sender] + 30 days, "Votes: Voting is still open");
        require(_token.allowance(msg.sender, address(this)) >= _tokensNeededForOwnership, "Votes: Not enough tokens allowed for transfer");
        require(_token.balanceOf(msg.sender) >= _tokensNeededForOwnership, "Votes: Not enough tokens for transfer");

        _initiateOwners[msg.sender] = block.timestamp;
        _token.transferFrom(msg.sender, address(this), _tokensNeededForOwnership);
        _balanceOwner[msg.sender] += _tokensNeededForOwnership;

        _proposedOwner = msg.sender;
        _votesForNewOwner = VoteResult(new address[](0), new address[](0), block.timestamp);
        emit InitiateOwnership(msg.sender, true);
    }

    // Voting function for accepting a new owner
    function voteForNewOwner(address _owner, bool vote) public onlyOwner canYouVote(_votesForNewOwner) {
        require(_proposedOwner != address(0) && _proposedOwner ==  _owner, "Votes: There is no active voting on this issue");

        (uint votestrue, uint votesfalse) = _votes(_votesForNewOwner, vote);

        emit VotingForNewOwner(msg.sender, _proposedOwner, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _owners[_proposedOwner] = true;
            _totalOwners++;
            _resetVote(_votesForNewOwner);
            emit VotingCompletedForNewOwner(msg.sender, _proposedOwner, vote, votestrue, votesfalse);
            _proposedOwner = address(0);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _token.transfer(_proposedOwner, _balanceOwner[msg.sender]);
            _resetVote(_votesForNewOwner);
            emit VotingCompletedForNewOwner(msg.sender, _proposedOwner, vote, votestrue, votesfalse);
            _proposedOwner = address(0);
        }
    }

    function startVotingForRemoveOwner(address _proposed) public onlyOwner canYouVote(_votesForStopped) {
        require(_proposed != address(0), "Votes: Cannot set null address");
        require(_owners[_proposed], "Votes: This address is not included in the list of owners");
        require(_proposedRemoveOwner == address(0), "Votes: Voting has already started");
        _proposedRemoveOwner = _proposed;
        _votesForRemoveOwner.timestamp = block.timestamp;
        _isOwnerVotedOut[_proposed] = true;
        _totalOwners--;
        _voteForRemoveOwner(true);
    }

    // The function of voting for the exclusion of the owner, while his deposit is confiscated
    function voteForRemoveOwner(bool vote) public onlyOwner canYouVote(_votesForRemoveOwner) {
        _voteForRemoveOwner(vote);
    }

    function _voteForRemoveOwner(bool vote) internal {
        require(_proposedRemoveOwner != msg.sender, "You cannot vote for yourself");
        require(_proposedRemoveOwner != address(0), "Votes: There is no active voting on this issue");

        (uint votestrue, uint votesfalse) = _votes(_votesForRemoveOwner, vote);

        emit VotingForRemoveOwner(msg.sender, _proposedOwner, vote);

        if (votestrue * 100 >= _totalOwners * 60) {
            _owners[_proposedRemoveOwner] = false;
            _resetVote(_votesForRemoveOwner);
            _balanceOwner[msg.sender] = 0;
            _isOwnerVotedOut[_proposedRemoveOwner] = false;
            _blackList[_proposedRemoveOwner] = true;
            emit VotingCompletedForRemoveOwner(msg.sender, _proposedOwner, vote, votestrue, votesfalse);
            _proposedRemoveOwner = address(0);
        } else if (votesfalse * 100 > _totalOwners * 40) {
            _owners[_proposedRemoveOwner] = false;
            _totalOwners++;
            _resetVote(_votesForRemoveOwner);
            _isOwnerVotedOut[_proposedRemoveOwner] = false;
            emit VotingCompletedForRemoveOwner(msg.sender, _proposedOwner, vote, votestrue, votesfalse);
            _proposedRemoveOwner = address(0);
        }
    }

    // The following functions are designed to close the vote if more than 3 days have passed and no decision has been made

    function closeVoteForStopped() public onlyOwner {
        require(_stopped != _proposedStopped, "There is no open vote");
        emit CloseVoteForStopped(msg.sender, _votesForStopped.isTrue.length, _votesForStopped.isFalse.length);
        _resetVote(_votesForStopped);
        _proposedStopped = _stopped;
        _increaseByPercent(msg.sender);
    }

    function closeVoteForTokensNeeded() public onlyOwner {
        require(_proposedTokensNeeded != 0, "There is no open vote");
        emit CloseVoteForStopped(msg.sender, _votesForTokensNeeded.isTrue.length, _votesForTokensNeeded.isFalse.length);
        _resetVote(_votesForTokensNeeded);
        _proposedTokensNeeded = 0;
        _increaseByPercent(msg.sender);
    }

    function closeVoteForNewImplementation() public onlyOwner {
        emit CloseVoteForNewImplementation(msg.sender, _votesForNewImplementation.isTrue.length, _votesForNewImplementation.isFalse.length);
        _closeVote(_votesForNewImplementation, _proposedImplementation);
    }

    function closeVoteForNewOwner() public onlyOwner {
        _token.transfer(_proposedOwner, _balanceOwner[msg.sender]);
        emit CloseVoteForNewOwner(msg.sender, _proposedOwner, _votesForNewOwner.isTrue.length, _votesForNewOwner.isFalse.length);
        _closeVote(_votesForNewOwner, _proposedOwner);
    }

    function closeVoteForRemoveOwner() public onlyOwner {
        _isOwnerVotedOut[_proposedRemoveOwner] = false;
        emit CloseVoteForRemoveOwner(msg.sender, _proposedRemoveOwner, _votesForRemoveOwner.isTrue.length, _votesForRemoveOwner.isFalse.length);
        _closeVote(_votesForRemoveOwner, _proposedRemoveOwner);
        _totalOwners++;
    }

    // Internal functions

    function _votes(VoteResult storage result, bool vote) internal returns (uint256, uint256) {
        if (vote) {
            result.isTrue.push(msg.sender);
        } else {
            result.isFalse.push(msg.sender);
        }
        return (result.isTrue.length, result.isFalse.length);
    }

    function _getVote(VoteResult memory vote, address addresess) private pure returns (address, uint256, uint256, uint256) {
        return (
            addresess, 
            vote.isTrue.length, 
            vote.isFalse.length, 
            vote.timestamp
        );
    }

    function _resetVote(VoteResult storage vote) internal {
        _increaseByPercent(vote.isTrue, vote.isFalse);
        vote.isTrue = new address[](0);
        vote.isFalse = new address[](0);
        vote.timestamp = 0;
    }

    function _closeVote(VoteResult storage vote, address propose) private canClose(propose, vote.timestamp) {
        _resetVote(vote);
        propose = address(0);
        _increaseByPercent(msg.sender);
    }

    function _increaseByPercent(address recepient) private {
        uint256 percent = _tokensNeededForOwnership * 1 / 1000;
        _balanceOwner[recepient] += percent;
    }

    function _increaseByPercent(address[] memory addresses1, address[] memory addresses2) private {
        for (uint256 i = 0; i < addresses1.length; i++) {
            _increaseByPercent(addresses1[i]);
        }

        for (uint256 j = 0; j < addresses2.length; j++) {
            _increaseByPercent(addresses2[j]);
        }
    }

}

interface IAnhydriteGlobal {
    function getTokens(address to, uint256 amount) external returns (bool);
}