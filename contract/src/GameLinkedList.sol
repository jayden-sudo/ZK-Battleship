// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library GameLinkedList {
    uint256 internal constant SENTINEL_UINT256 = 1;

    modifier onlyUint256(uint256 data) {
        require(data > SENTINEL_UINT256, "INVALID_DATA");
        _;
    }

    function add(
        mapping(uint256 => uint256) storage self,
        uint256 data
    ) internal onlyUint256(data) {
        require(self[data] == 0, "DATA_ALREADY_EXISTS");
        uint256 _prev = self[SENTINEL_UINT256];
        if (_prev == 0) {
            self[SENTINEL_UINT256] = data;
            self[data] = SENTINEL_UINT256;
        } else {
            self[SENTINEL_UINT256] = data;
            self[data] = _prev;
        }
    }

    function remove(
        mapping(uint256 => uint256) storage self,
        uint256 data
    ) internal {
        require(tryRemove(self, data), "DATA_NOT_EXISTS");
    }

    function tryRemove(
        mapping(uint256 => uint256) storage self,
        uint256 data
    ) internal returns (bool) {
        if (isExist(self, data)) {
            uint256 cursor = SENTINEL_UINT256;
            while (true) {
                uint256 _data = self[cursor];
                if (_data == data) {
                    uint256 next = self[_data];
                    self[cursor] = next;
                    self[_data] = 0;
                    return true;
                }
                cursor = _data;
            }
        }
        return false;
    }

    function isExist(
        mapping(uint256 => uint256) storage self,
        uint256 data
    ) internal view onlyUint256(data) returns (bool) {
        return self[data] != 0;
    }

    function size(
        mapping(uint256 => uint256) storage self
    ) internal view returns (uint256) {
        uint256 result = 0;
        uint256 data = self[SENTINEL_UINT256];
        while (data > SENTINEL_UINT256) {
            data = self[data];
            unchecked {
                result++;
            }
        }
        return result;
    }

    function isEmpty(
        mapping(uint256 => uint256) storage self
    ) internal view returns (bool) {
        return self[SENTINEL_UINT256] == 0;
    }

    function list(
        mapping(uint256 => uint256) storage self,
        uint256 from,
        uint256 limit
    ) internal view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](limit);
        uint256 i = 0;
        uint256 data = self[from];
        while (data > SENTINEL_UINT256 && i < limit) {
            result[i] = data;
            data = self[data];
            unchecked {
                i++;
            }
        }

        return result;
    }
}
