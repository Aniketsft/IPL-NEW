namespace EnterpriseAuth.Api.Internal
{
    public interface ISqlDataAccess
    {
        void CommitTransaction();
        void Dispose();
        string GetConnectionString(string name);
        Task<IEnumerable<T>> LoadData<T, u>(string storedProcedure, u parameters, string connectionStringName);
        List<T> LoadDataInTransaction<T, u>(string storedProcedure, u parameters);
        Task<IEnumerable<T>> LoadDataRaw<T, u>(string sql, u parameters, string connectionStringName);
        void RollbackTransaction();
        Task SaveData<T>(string storedProcedure, T parameters, string connectionStringName);
        void SaveDataInTranscation<T>(string storedProcedure, T parameters);
        Task SaveDataRaw<T>(string sql, T parameters, string connectionStringName);
        void StartTranscation(string connectionStringName);
    }
}