<!-- App.vue -->
<template>
  <div id="app">
    <AppHeader @account-changed="updateAccount" />
    <PropertyList />
    <RentProperty />
    <RentalHistory />
    <MaintenanceRequest />
    <AppNotification />
  </div>
</template>

<script>
import AppHeader from './components/AppHeader.vue';
import PropertyList from './components/PropertyList.vue';
import RentProperty from './components/RentProperty.vue';
import RentalHistory from './components/RentalHistory.vue';
import MaintenanceRequest from './components/MaintenanceRequest.vue';
import AppNotification from './components/AppNotification.vue';
import Web3 from 'web3';
import RentalManagementABI from '../../RentChain/out/RentalManagement.sol/RentalManagement.json';


export default {
  components: {
    AppHeader,
    PropertyList,
    RentProperty,
    RentalHistory,
    MaintenanceRequest,
    AppNotification
  },
  data() {
    return {
      web3: null,
      contract: null,
      account: null
    };
  },
  methods: {
    updateAccount(account) {
      this.account = account;
      if (this.contract) {
        this.contract.options.from = account;
      }
    }
  },
  async mounted() {
    if (window.ethereum) {
      this.web3 = new Web3(window.ethereum);
      await window.ethereum.request({ method: 'eth_requestAccounts' });
      this.account = (await this.web3.eth.getAccounts())[0];
      this.contract = new this.web3.eth.Contract(
        RentalManagementABI.abi,
        '0x2b602d2f559a0badf4d5956d03f2b330fbc2e9f9'
      );
    } else {
      alert("Please install MetaMask or another Ethereum wallet.");
    }
  }
};
</script>

