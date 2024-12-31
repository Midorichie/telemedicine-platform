// tests/consultation_test.ts

import {
  Client,
  Provider,
  ProviderRegistry,
  Result,
} from "@blockstack/clarity";

describe("telemedicine consultation contract test suite", () => {
  let client: Client;
  let provider: Provider;

  const doctorAddress = "ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM";
  const patientAddress = "ST2CY5V39NHDPWSXMW9QDT3HC3GD6Q6XX4CFRK9AG";
  const verifierAddress = "ST2JHG361ZXG51QTKY2NQCVBPPRRE2KZB1HR05NNC";

  beforeEach(async () => {
    provider = await ProviderRegistry.createProvider();
    client = new Client("SP3GWX3NE58KXHESRYE4DYQ1S31PQJTCRXB3PE9SB.telemedicine-consultation");
  });

  afterEach(async () => {
    await provider.close();
  });

  describe("doctor registration", () => {
    it("successfully registers a new doctor", async () => {
      const execution = await client.executeMethod(
        doctorAddress,
        "register-doctor",
        ["Cardiology   "]
      );
      expect(execution.success).toBe(true);
    });

    it("fails with invalid specialization", async () => {
      const execution = await client.executeMethod(
        doctorAddress,
        "register-doctor",
        ["InvalidSpec  "]
      );
      expect(execution.success).toBe(false);
    });
  });

  describe("consultation scheduling", () => {
    beforeEach(async () => {
      // Setup: Register and verify doctor
      await client.executeMethod(doctorAddress, "register-doctor", ["Cardiology   "]);
      await client.executeMethod(verifierAddress, "verify-doctor", [doctorAddress]);
    });

    it("successfully schedules consultation", async () => {
      const execution = await client.executeMethod(
        patientAddress,
        "schedule-consultation-with-time",
        [doctorAddress, "u100000", "u1000", "u30"]
      );
      expect(execution.success).toBe(true);
    });

    it("fails with unverified doctor", async () => {
      const unverifiedDoctor = "ST2ZRX0K27GW0SP3GJCEMHD95TQGJMKB7G9Y0X1MH";
      const execution = await client.executeMethod(
        patientAddress,
        "schedule-consultation-with-time",
        [unverifiedDoctor, "u100000", "u1000", "u30"]
      );
      expect(execution.success).toBe(false);
    });
  });

  describe("consultation management", () => {
    let consultationId: string;

    beforeEach(async () => {
      // Setup: Create a consultation
      await client.executeMethod(doctorAddress, "register-doctor", ["Cardiology   "]);
      await client.executeMethod(verifierAddress, "verify-doctor", [doctorAddress]);
      const result = await client.executeMethod(
        patientAddress,
        "schedule-consultation-with-time",
        [doctorAddress, "u100000", "u1000", "u30"]
      );
      consultationId = result.value;
    });

    it("doctor can start consultation", async () => {
      const execution = await client.executeMethod(
        doctorAddress,
        "start-consultation",
        [consultationId]
      );
      expect(execution.success).toBe(true);
    });

    it("doctor can complete consultation", async () => {
      await client.executeMethod(doctorAddress, "start-consultation", [consultationId]);
      const execution = await client.executeMethod(
        doctorAddress,
        "complete-consultation",
        [consultationId, "0x0123456789abcdef"]
      );
      expect(execution.success).toBe(true);
    });

    it("patient can rate completed consultation", async () => {
      await client.executeMethod(doctorAddress, "start-consultation", [consultationId]);
      await client.executeMethod(
        doctorAddress,
        "complete-consultation",
        [consultationId, "0x0123456789abcdef"]
      );
      const execution = await client.executeMethod(
        patientAddress,
        "rate-consultation",
        [consultationId, "u5"]
      );
      expect(execution.success).toBe(true);
    });
  });
});

// Additional test files for patient-records and doctor-registry would follow 
// a similar pattern
