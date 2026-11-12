package ai.allo.car.sync

/** Fixed Android-emulator routing; production configuration is never accepted as a local target. */
data class FirebaseEndpoints private constructor(
    val databaseUrl: String,
    val databaseNamespace: String?,
    val identityUrl: String,
    val refreshUrl: String,
    val sessionUrl: String,
    val local: Boolean,
) {
    companion object {
        fun resolve(debug: Boolean, emulator: Boolean, project: String, region: String, databaseUrl: String): FirebaseEndpoints {
            if (debug && emulator) {
                require(project == "demo-allo-auth" && region == "asia-northeast3")
                require(databaseUrl == "https://demo-allo-auth-default-rtdb.firebaseio.com")
                return FirebaseEndpoints("http://10.0.2.2:9000", "demo-allo-auth-default-rtdb",
                    "http://10.0.2.2:9099/identitytoolkit.googleapis.com/v1/accounts:signUp",
                    "http://10.0.2.2:9099/securetoken.googleapis.com/v1/token",
                    "http://10.0.2.2:5001/demo-allo-auth/asia-northeast3/createVehicleSession", true)
            }
            return FirebaseEndpoints(databaseUrl, null,
                "https://identitytoolkit.googleapis.com/v1/accounts:signUp",
                "https://securetoken.googleapis.com/v1/token",
                "https://$region-$project.cloudfunctions.net/createVehicleSession", false)
        }
    }
}
