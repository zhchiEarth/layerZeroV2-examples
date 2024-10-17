// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script, stdJson, console2 as console} from "forge-std/Script.sol";

/// @notice store the new deployment to be saved
struct Deployment {
    string name;
    address payable addr;
}

/// @title Deployer
/// @author tynes
/// @notice A contract that can make deploying and interacting with deployments easy.
///         When a contract is deployed, call the `save` function to write its name and
///         contract address to disk. Then the `sync` function can be called to generate
///         hardhat deploy style artifacts. Forked from `forge-deploy`.
abstract contract Deployer is Script {
    /// @notice The set of deployments that have been done during execution.
    mapping(string => Deployment) internal _namedDeployments;
    /// @notice The same as `_namedDeployments` but as an array.
    Deployment[] internal _newDeployments;
    /// @notice The namespace for the deployment. Can be set with the env var DEPLOYMENT_CONTEXT.
    string internal deploymentContext;
    string internal projectName;
    string internal environment;
    /// @notice Path to the deploy artifact generated by foundry
    string internal deployPath;
    /// @notice Path to the directory containing the hh deploy style artifacts
    string internal deploymentsDir;
    /// @notice The name of the deploy script that sends the transactions.
    ///         Can be modified with the env var DEPLOY_SCRIPT
    string internal deployScript;
    /// @notice The path to the temp deployments file
    string internal tempDeploymentsPath;

    Chains chainContract;

    /// @notice Error for when attempting to fetch a deployment and it does not exist
    error DeploymentDoesNotExist(string);
    /// @notice Error for when trying to save an invalid deployment
    error InvalidDeployment(string);

    /// @notice The storage slot that holds the address of the implementation.
    ///        bytes32(uint256(keccak256('eip1967.proxy.implementation')) - 1)
    bytes32 internal constant IMPLEMENTATION_KEY = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    /// @notice The storage slot that holds the address of the owner.
    ///        bytes32(uint256(keccak256('eip1967.proxy.admin')) - 1)
    bytes32 internal constant OWNER_KEY = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function setUp() public virtual {
        chainContract = new Chains();
        string memory root = vm.projectRoot();

        deploymentContext = _getDeploymentContext(block.chainid);
        uint256 chainId = vm.envOr("CHAIN_ID", block.chainid);

        if (keccak256(abi.encodePacked(projectName)) != keccak256("")) {
            deploymentsDir = string.concat(root, "/deployments/", projectName, deploymentContext);
        } else {
            deploymentsDir = string.concat(root, "/deployments/", deploymentContext);
        }

        try vm.createDir(deploymentsDir, true) {} catch (bytes memory) {}

        string memory chainIdPath = string.concat(deploymentsDir, "/.chainId");
        try vm.readFile(chainIdPath) returns (string memory localChainId) {
            if (vm.envOr("STRICT_DEPLOYMENT", true)) {
                require(vm.parseUint(localChainId) == chainId, "Misconfigured networks");
            }
        } catch {
            vm.writeFile(chainIdPath, vm.toString(chainId));
        }
        console.log("Connected to network with chainid %s", chainId);

        tempDeploymentsPath = string.concat(deploymentsDir, "/deploy", environment, ".json");
        try vm.readFile(tempDeploymentsPath) returns (string memory) {}
        catch {
            vm.writeJson("{}", tempDeploymentsPath);
        }
        console.log("Storing temp deployment data in %s", tempDeploymentsPath);
    }

    //     /// @notice Returns the name of the deployment script. Children contracts
    //     ///         must implement this to ensure that the deploy artifacts can be found.
    //     function name() public pure virtual returns (string memory);

    /// @notice Returns all of the deployments done in the current context.
    function newDeployments() external view returns (Deployment[] memory) {
        return _newDeployments;
    }

    /// @notice Returns whether or not a particular deployment exists.
    /// @param _name The name of the deployment.
    /// @return Whether the deployment exists or not.
    function has(string memory _name) public view returns (bool) {
        Deployment memory existing = _namedDeployments[_name];
        if (existing.addr != address(0)) {
            return bytes(existing.name).length > 0;
        }
        return _getExistingDeploymentAddress(_name) != address(0);
    }

    /// @notice Returns the address of a deployment.
    /// @param _name The name of the deployment.
    /// @return The address of the deployment. May be `address(0)` if the deployment does not
    ///         exist.
    function getAddress(string memory _name) public view returns (address payable) {
        Deployment memory existing = _namedDeployments[_name];
        if (existing.addr != address(0)) {
            if (bytes(existing.name).length == 0) {
                return payable(address(0));
            }
            return existing.addr;
        }
        return _getExistingDeploymentAddress(_name);
    }

    /// @notice Returns the address of a deployment and reverts if the deployment
    ///         does not exist.
    /// @return The address of the deployment.
    function mustGetAddress(string memory _name) public view returns (address payable) {
        address addr = getAddress(_name);
        if (addr == address(0)) {
            revert DeploymentDoesNotExist(_name);
        }
        return payable(addr);
    }

    /// @notice Returns a deployment that is suitable to be used to interact with contracts.
    /// @param _name The name of the deployment.
    /// @return The deployment.
    function get(string memory _name) public view returns (Deployment memory) {
        Deployment memory deployment = _namedDeployments[_name];
        if (deployment.addr != address(0)) {
            return deployment;
        } else {
            return _getExistingDeployment(_name);
        }
    }

    /// @notice Writes a deployment to disk as a temp deployment so that the
    ///         hardhat deploy artifact can be generated afterwards.
    /// @param _name The name of the deployment.
    /// @param _deployed The address of the deployment.
    function save(string memory _name, address _deployed) public {
        if (bytes(_name).length == 0) {
            revert InvalidDeployment("EmptyName");
        }
        if (bytes(_namedDeployments[_name].name).length > 0) {
            revert InvalidDeployment("AlreadyExists");
        }

        Deployment memory deployment = Deployment({name: _name, addr: payable(_deployed)});
        _namedDeployments[_name] = deployment;
        _newDeployments.push(deployment);
        _writeTemp(_name, _deployed);
    }

    /// @notice Returns the contract name from a deploy transaction.
    function _getContractNameFromDeployTransaction(string memory _deployTx) internal returns (string memory) {
        return stdJson.readString(_deployTx, ".contractName");
    }

    /// @notice Adds a deployment to the temp deployments file
    function _writeTemp(string memory _name, address _deployed) internal {
        if (_getExistingDeploymentAddress(_name) != address(0)) {
            vm.writeJson({json: vm.toString(_deployed), path: tempDeploymentsPath, valueKey: string.concat("$.", _name)});
        } else {
            vm.writeJson({json: stdJson.serialize("", _name, _deployed), path: tempDeploymentsPath});
        }
    }

    /// @notice The context of the deployment is used to namespace the artifacts.
    ///         An unknown context will use the chainid as the context name.
    function _getDeploymentContext(uint256 chainid) internal returns (string memory) {
        string memory context = vm.envOr("DEPLOYMENT_CONTEXT", string(""));
        if (bytes(context).length > 0) {
            return context;
        }

        return chainContract.getChainAlice(chainid);
    }

    /// @notice Reads the artifact from the filesystem by name and returns the address.
    /// @param _name The name of the artifact to read.
    /// @return The address of the artifact.
    function _getExistingDeploymentAddress(string memory _name) internal view returns (address payable) {
        return _getExistingDeployment(_name).addr;
    }

    /// @notice Reads the artifact from the filesystem by name and returns the Deployment.
    /// @param _name The name of the artifact to read.
    /// @return The deployment corresponding to the name.
    function _getExistingDeployment(string memory _name) internal view returns (Deployment memory) {
        // string memory path = string.concat(deploymentsDir, "/", _name, ".json");
        string memory path = tempDeploymentsPath;
        try vm.readFile(path) returns (string memory json) {
            bytes memory addr = stdJson.parseRaw(json, string.concat("$.", _name));
            address payable newAddr;
            if (addr.length == 0) {
                newAddr = payable(address(0));
            } else {
                newAddr = abi.decode(addr, (address));
                if (isZeroAddress(newAddr)) {
                    newAddr = payable(address(0));
                }
            }

            return Deployment({addr: newAddr, name: _name});
        } catch {
            return Deployment({addr: payable(address(0)), name: ""});
        }
    }

    function isZeroAddress(address addr_) public pure returns (bool) {
        return addr_ == address(32) || addr_ == address(0) || addr_ == address(64);
    }
}
