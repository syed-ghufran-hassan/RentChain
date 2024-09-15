<template>
  <div>
    <h2>Rent Property</h2>
    <form @submit.prevent="rentProperty">
      <label for="propertyId">Property ID:</label>
      <input type="number" v-model="propertyId" id="propertyId" required />

      <label for="rentalStart">Rental Start (timestamp):</label>
      <input type="number" v-model="rentalStart" id="rentalStart" required />

      <label for="rentalEnd">Rental End (timestamp):</label>
      <input type="number" v-model="rentalEnd" id="rentalEnd" required />

      <button type="submit">Rent Property</button>
    </form>
  </div>
</template>

<script>
export default {
  data() {
    return {
      propertyId: '',
      rentalStart: '',
      rentalEnd: '',
    };
  },
  methods: {
    async rentProperty() {
      const contract = this.$root.contract;
      const rentAmount = this.$root.web3.utils.toWei('1', 'ether');
      try {
        await contract.methods.rentProperty(
          this.propertyId,
          this.rentalStart,
          this.rentalEnd
        ).send({ from: this.$root.account, value: rentAmount });
        alert('Property rented successfully!');
      } catch (error) {
        console.error("Error renting property", error);
      }
    }
  }
};
</script>
