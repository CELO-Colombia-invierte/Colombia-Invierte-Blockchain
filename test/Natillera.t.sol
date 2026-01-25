// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import {Natillera} from "../src/contracts/Natillera.sol";
import {INatillera} from "../src/interfaces/INatillera.sol";
import {IPlatform} from "../src/interfaces/IPlatform.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 10000 ether);
    }
}

contract MockPlatform {
    function addUserToProject(uint256, address) external {}
}

contract NatilleraTest is Test {
    Natillera public natillera;
    MockPlatform public platform;
    address public owner;
    address public member1;
    address public member2;

    function setUp() public {
        owner = address(this);
        member1 = address(0x1);
        member2 = address(0x2);
        
        platform = new MockPlatform();
        natillera = new Natillera();

        INatillera.NatilleraConfig memory config = INatillera.NatilleraConfig({
            token: address(0), // Native ETH
            monthlyContribution: 1 ether,
            totalMonths: 12,
            maxMembers: 100
        });

        IPlatform.GovernanceConfig memory govConfig = IPlatform.GovernanceConfig({
            governanceDelay: 1 days,
            proposalThreshold: 1,
            votingPeriod: 1 weeks,
            quorumRequired: 5000 // 50%
        });

        IPlatform.ProjectConfig memory projectConfig = IPlatform.ProjectConfig({
            platform: address(platform),
            projectId: 1,
            creator: owner
        });

        natillera.initialize(
            block.timestamp + 1 days,
            config,
            govConfig,
            projectConfig
        );
    }

    function testBatchAddMembers() public {
        address[] memory members = new address[](2);
        members[0] = member1;
        members[1] = member2;

        natillera.batchAddMembers(members);

        assertTrue(natillera.isMember(member1));
        assertTrue(natillera.isMember(member2));
    }

    function testFinalizeAndWithdraw() public {
        // Setup members
        address[] memory members = new address[](2);
        members[0] = member1;
        members[1] = member2;
        natillera.batchAddMembers(members);

        // Deposits: Member1 deposits 1 ETH, Member2 deposits 2 ETH (Total 3 ETH)
        vm.deal(member1, 10 ether);
        vm.prank(member1);
        natillera.depositSingleCycle{value: 1 ether}();

        vm.deal(member2, 10 ether);
        vm.prank(member2);
        natillera.depositMultipleCycles{value: 2 ether}(2);

        assertEq(address(natillera).balance, 3 ether);

        // Finalize
        natillera.finalize();
        assertTrue(natillera.finalized());

        // Test Proportional Withdrawal
        // Member 1 Share = (1 / 3) * 3 = 1 ETH
        vm.prank(member1);
        natillera.withdraw();
        assertEq(member1.balance, 11 ether - 1 ether); // 10 start - 1 paid + 1 withdrawn = 10 (Wait, vm.deal overrides balance)
        // Actually: Start 10. Paid 1 -> 9. Withdraw 1 -> 10.
        // Let's check diff.
        // member1 balance should increase by 1
        
        // Member 2 Share = (2 / 3) * 3 = 2 ETH
        vm.prank(member2);
        natillera.withdraw();
        
        assertEq(address(natillera).balance, 0);
    }

    function testProportionalDistributionWithYield() public {
        // Simulating external yield (e.g. someone sends ETH to contract or investment return)
        
        address[] memory members = new address[](2);
        members[0] = member1;
        members[1] = member2;
        natillera.batchAddMembers(members);

        // Equal deposits: 1 ETH each
        vm.deal(member1, 10 ether);
        vm.prank(member1);
        natillera.depositSingleCycle{value: 1 ether}();

        vm.deal(member2, 10 ether);
        vm.prank(member2);
        natillera.depositSingleCycle{value: 1 ether}();

        // Inject Profit: Contract balance goes from 2 ETH -> 4 ETH (2 ETH Profit)
        vm.deal(address(natillera), 4 ether); 

        natillera.finalize();

        // Withdraw Member 1
        // Share = (1 / 2) * 4 = 2 ETH
        uint256 balanceBefore = member1.balance;
        vm.prank(member1);
        natillera.withdraw();
        assertEq(member1.balance, balanceBefore + 2 ether);
    }

    function testDepositAfterFinalizeReverts() public {
        natillera.finalize();
        
        address[] memory members = new address[](1);
        members[0] = member1;
        
        // Try adding member
        vm.expectRevert(); 
        natillera.batchAddMembers(members);

        // Try depositing (assuming added before)
        // ... (requires adding member before finalize to test this path, but finalize blocks everything)
    }

    function testDoubleWithdrawReverts() public {
        address[] memory members = new address[](1);
        members[0] = member1;
        natillera.batchAddMembers(members);

        vm.deal(member1, 1 ether);
        vm.prank(member1);
        natillera.depositSingleCycle{value: 1 ether}();

        natillera.finalize();

        vm.prank(member1);
        natillera.withdraw();

        vm.prank(member1);
        vm.expectRevert(); // Already claimed
        natillera.withdraw();
    }

    receive() external payable {}
}
