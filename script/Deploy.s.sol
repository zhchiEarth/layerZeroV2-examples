// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import {Script, console} from "forge-std/Script.sol";
import {LzMessage} from "src/LzMessage.sol";
import {OptionsBuilder} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/libs/OptionsBuilder.sol";
import {MessagingFee} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";

contract DeployScript is Script {
    address owner = 0x10435c946C61426C3fE60eCa113f70493D5415c7;

    function setUp() public {}

    function run() public {}

    // forge script script/Deploy.s.sol:DeployScript --sig "deploy(address)" --rpc-url $rpc --private-key $ZK_PRIVATE_KEY --broadcast --etherscan-api-key $BNB_API_KEY --verify
    function deploy(address endpoint_) public {
        vm.broadcast();
        new LzMessage(endpoint_, owner);
    }

    function setPeer(address lzMessageAddr, uint32 _eid, address _peer) public {
        LzMessage lzMessage = LzMessage(lzMessageAddr);
        vm.broadcast();
        lzMessage.setPeer(_eid, bytes32(uint256(uint160(addr))));
    }

    function sendMessage(address lzMessageAddr, string calldata msg_, uint32 dstEid_) public {
        LzMessage lzMessage = LzMessage(lzMessageAddr);

        uint128 _gas = 100000;
        uint128 _value = 0;

        bytes option = OptionsBuilder.newOptions().addExecutorLzReceiveOption(_gas, _value);
        MessagingFee fee = lzMessage.quote(dstEid_, msg_, option, false);
        vm.broadcast();
        lzMessage.send{value: fee.nativeFee}(dstEid_, msg_, option);
    }
}
