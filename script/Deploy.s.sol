// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {LzMessage} from "src/LzMessage.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract DeployScript is Script {
    using OptionsBuilder for bytes;

    address owner = 0x10435c946C61426C3fE60eCa113f70493D5415c7;

    function setUp() public {}

    function run() public {}

    // forge script script/Deploy.s.sol:DeployScript --sig "deploy(address)" --rpc-url $rpc --private-key $ZK_PRIVATE_KEY --broadcast --etherscan-api-key $BNB_API_KEY --verify

    // forge script --account zk_deploy_account script/Deploy.s.sol:DeployScript --sig "deploy(address)" 0x6EDCE65403992e310A62460808c4b910D972f10f --rpc-url $BNB_TESTNET_RPC_URL  --broadcast --etherscan-api-key $BNB_API_KEY --verify
    // https://testnet.bscscan.com/address/0x6b29116fa0b45da63be3fcedd58a0ac99084f921
    // eid 40102

    // forge script --account zk_deploy_account script/Deploy.s.sol:DeployScript --sig "deploy(address)" 0x6EDCE65403992e310A62460808c4b910D972f10f --rpc-url $$SEPOLIA_RPC_URL  --broadcast --etherscan-api-key $MAINNET_API_KEY --verify
    // https://sepolia.etherscan.io/address/0x034d142c4f3dbe3b0fffd7236c945ab60e0853a8
    // eid 40161
    function deploy(address endpoint_) public {
        vm.broadcast();
        new LzMessage(endpoint_, owner);
    }

    function setPeer(address lzMessageAddr, uint32 eid_, address peer_) public {
        LzMessage lzMessage = LzMessage(lzMessageAddr);
        vm.broadcast();
        lzMessage.setPeer(eid_, bytes32(uint256(uint160(peer_))));
    }

    function sendMessage(address lzMessageAddr, string calldata msg_, uint32 dstEid_) public {
        LzMessage lzMessage = LzMessage(lzMessageAddr);

        uint128 _gas = 100000;
        uint128 _value = 0;

        // bytes memory option = OptionsBuilder.newOptions();
        bytes memory option = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
        MessagingFee memory fee = lzMessage.quote(dstEid_, msg_, option, false);
        vm.broadcast();
        lzMessage.send{value: fee.nativeFee}(dstEid_, msg_, option);
    }
}
