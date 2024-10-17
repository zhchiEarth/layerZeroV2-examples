// SPDX-License-Identifier: MIT

pragma solidity ^0.8.22;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OApp, MessagingFee, Origin} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OApp.sol";
import {MessagingReceipt} from "@layerzerolabs/lz-evm-oapp-v2/contracts/oapp/OAppSender.sol";
import {SetConfigParam} from "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import {UlnConfig} from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";

contract LzMessage is OApp {
    string public message;

    constructor(address _endpoint) OApp(_endpoint, msg.sender) Ownable(msg.sender) {}

    event Send(uint32 dstEid, string message, bytes payload, MessagingReceipt messageReceipt);
    event Receive(Origin origin, bytes32 guid, bytes payload, address executor, bytes extraData, string parseMsg);

    /**
     * @notice Sends a message from the source chain to a destination chain.
     * @param _dstEid The endpoint ID of the destination chain.
     * @param _message The message string to be sent.
     * @param _options Additional options for message execution.
     * @dev Encodes the message as bytes and sends it using the `_lzSend` internal function.
     * @return receipt A `MessagingReceipt` struct containing details of the message sent.
     */
    function send(uint32 _dstEid, string memory _message, bytes calldata _options)
        external
        payable
        returns (MessagingReceipt memory receipt)
    {
        bytes memory _payload = abi.encode(_message);
        receipt = _lzSend(_dstEid, _payload, _options, MessagingFee(msg.value, 0), payable(msg.sender));
        emit Send(_dstEid, _message, _payload, receipt);
    }

    /**
     * @notice Quotes the gas needed to pay for the full omnichain transaction in native gas or ZRO token.
     * @param _dstEid Destination chain's endpoint ID.
     * @param _message The message.
     * @param _options Message execution options (e.g., for sending gas to destination).
     * @param _payInLzToken Whether to return fee in ZRO token.
     * @return fee A `MessagingFee` struct containing the calculated gas fee in either the native token or ZRO token.
     */
    function quote(uint32 _dstEid, string memory _message, bytes memory _options, bool _payInLzToken)
        public
        view
        returns (MessagingFee memory fee)
    {
        bytes memory payload = abi.encode(_message);
        fee = _quote(_dstEid, payload, _options, _payInLzToken);
    }

    function _lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _payload,
        address _executor,
        bytes calldata _extraData
    ) internal override {
        message = abi.decode(_payload, (string));
        emit Receive(_origin, _guid, _payload, _executor, _extraData, message);
    }

    function setPeer(uint32 _eid, bytes32 _peer) public virtual override {
        peers[_eid] = _peer;
        emit PeerSet(_eid, _peer);
    }

    function setZkLightClient(uint32 eid, address zkLightClient) external {
        address[] memory requiredDVNs = new address[](1);
        requiredDVNs[0] = zkLightClient;
        address[] memory optionalDVNs = new address[](0);

        UlnConfig memory ulnConfig = UlnConfig({
            confirmations: 0, // default confirmations
            requiredDVNCount: 1,
            optionalDVNCount: 0,
            optionalDVNThreshold: 0,
            requiredDVNs: requiredDVNs,
            optionalDVNs: optionalDVNs
        });

        SetConfigParam[] memory _params = new SetConfigParam[](1);
        _params[0] = SetConfigParam({eid: eid, configType: 2, config: abi.encode(ulnConfig)});

        address sendLibrary = endpoint.getSendLibrary(address(this), eid);
        endpoint.setConfig(address(this), sendLibrary, _params);
        (address receiveLibrary,) = endpoint.getReceiveLibrary(address(this), eid);
        if (sendLibrary != receiveLibrary) {
            endpoint.setConfig(address(this), receiveLibrary, _params);
        }
    }
}
