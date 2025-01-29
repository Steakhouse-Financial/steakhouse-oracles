// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

/// @title IOracle
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Interface that oracles used by Morpho must implement.
/// @dev It is the user's responsibility to select markets with safe oracles.
interface IOracle {
    /// @notice Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
    /// @dev It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
    /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals`
    /// decimals of precision.
    function price() external view returns (uint256);
}

contract MetaOracleDeviationTimelock is IOracle { 
    IOracle public oracle; // Currently selected oracle
    IOracle public primaryOracle;
    IOracle public backupOracle;
    uint256 public timelock;
    uint256 public challengeTimelock = 0;
    uint256 public healingTimelock = 0;
    uint256 public threshold;

    function price() public view returns (uint256) {
        return oracle.price();
    }

    function isPrimary() public view returns (bool) {
        return oracle == primaryOracle;
    }

    function isBackup() public view returns (bool) {
        return oracle == backupOracle;
    }

    function isChallenged() public view returns (bool) {
        return challengeTimelock > 0;
    }

    function isHealing() public view returns (bool) {
        return healingTimelock > 0;
    }

    function isDeviant() public view returns (bool) {
        uint256 primaryPrice = primaryOracle.price();
        uint256 backupPrice = backupOracle.price();

        // Yes should depends on which is greater
        uint256 deviation = (primaryPrice - backupPrice) * 10**18 / backupPrice;

        return (deviation > threshold);
    }

    function challenge() public {
        require(isPrimary(), "Work only if primary is selected");
        require(!isChallenged(), "Shouldn't be challenged already");
        require(isDeviant(), "Require deviation");
        
        challengeTimelock = block.timestamp + timelock;
    }

    function revokeChallenge() public {
        require(isPrimary(), "Work only if primary is selected");
        require(isChallenged(), "Should be in a challenge");
        require(!isDeviant(), "Require no deviation");

        challengeTimelock = 0;
    }

    function acceptChallenge() public {
        require(isPrimary(), "Work only if primary is selected");
        require(isChallenged(), "Should be in a challenge");
        require(challengeTimelock > block.timestamp, "Shouldn't be after the challenge timelock");

        oracle = backupOracle;
        challengeTimelock = 0;
    }

    function heal() public {
        require(isBackup(), "Work only if backup is selected");
        require(!isHealing(), "Shouldn't be healing already");
        require(!isDeviant(), "Require no deviation");
        
        healingTimelock = block.timestamp + timelock;
    }

    function revokeHealing() public {
        require(isBackup(), "Work only if backup is selected");
        require(isHealing(), "Should be healing");
        require(isDeviant(), "Require deviation");

        healingTimelock = 0;
    }

    function acceptHealing() public {
        require(isBackup(), "Work only if backup is selected");
        require(isHealing(), "Should be healing");
        require(healingTimelock > block.timestamp, "Shouldn't be challenged already");

        oracle = primaryOracle;
        healingTimelock = 0;
    }
}