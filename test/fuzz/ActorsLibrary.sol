// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

struct SimulatedUsers {
    address[] senders;
    mapping(address sender => bool saved) isSaved;
}

library ActorsLibrary {
    function saveSender(SimulatedUsers storage su, address addr) internal {
        // add user to the list of senders if not added before
        if (su.isSaved[addr] == false) {
            su.senders.push(addr);
            su.isSaved[addr] = true;
        } else {
            // User is already saved so return
            return;
        }
    }

    function selectRandomSender(
        SimulatedUsers storage su,
        uint256 seed
    ) internal view returns (address selectedActor) {
        // Select a random actor from the list of actors
        if (su.senders.length > 0) {
            selectedActor = su.senders[seed % su.senders.length];
        }

        return selectedActor;
    }
}
