<template>
  <div>
    <h2>Rental History</h2>
    <h3>Tenant History</h3>
    <ul>
      <li v-for="record in tenantHistory" :key="record.propertyId">
        Property ID: {{ record.propertyId }} - Start: {{ new Date(record.rentalStart * 1000).toLocaleString() }} - End: {{ new Date(record.rentalEnd * 1000).toLocaleString() }} - Deposit: {{ record.deposit }} ETH
      </li>
    </ul>
    <h3>Owner History</h3>
    <ul>
      <li v-for="record in ownerHistory" :key="record.propertyId">
        Property ID: {{ record.propertyId }} - Start: {{ new Date(record.rentalStart * 1000).toLocaleString() }} - End: {{ new Date(record.rentalEnd * 1000).toLocaleString() }} - Deposit: {{ record.deposit }} ETH
      </li>
    </ul>
  </div>
</template>

<script>
export default {
  data() {
    return {
      tenantHistory: [],
      ownerHistory: [],
    };
  },
  methods: {
    async getRentalHistory() {
      const contract = this.$root.contract;
      const tenant = this.$root.account;
      const tenantHistory = await contract.methods.GettenantHistory(tenant, 0).call();
      const ownerHistory = await contract.methods.GetownerHistory(tenant, 0).call();
      this.tenantHistory = tenantHistory.map(record => ({
        ...record,
        deposit: this.$root.web3.utils.fromWei(record.deposit, 'ether'),
      }));
      this.ownerHistory = ownerHistory.map(record => ({
        ...record,
        deposit: this.$root.web3.utils.fromWei(record.deposit, 'ether'),
      }));
    }
  },
  mounted() {
    this.getRentalHistory();
  }
};
</script>
