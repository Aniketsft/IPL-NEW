using System.Data;
using System.Data.SqlClient;

using Dapper;

namespace EnterpriseAuth.Api.Internal
{
    public class SqlDataAccess : IDisposable, ISqlDataAccess
    {
        public SqlDataAccess(IConfiguration config, ILogger<SqlDataAccess> logger)
        {
            this.config = config;
            this.logger = logger;
        }

        public string GetConnectionString(string name)
        {
            return config.GetConnectionString(name);
        }

        [Obsolete]
        public async Task<IEnumerable<T>> LoadData<T, u>(string storedProcedure, u parameters, string connectionStringName)
        {
            try
            {
                string connectionString = GetConnectionString(connectionStringName);
                using (IDbConnection connection = new SqlConnection(connectionString))
                {
                    var rows = await connection.QueryAsync<T>(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
                    return rows;
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        public async Task<IEnumerable<T>> LoadDataRaw<T, u>(string sql, u parameters, string connectionStringName)
        {
            try
            {
                string connectionString = GetConnectionString(connectionStringName);
                using (IDbConnection connection = new SqlConnection(connectionString))
                {
                    var rows = await connection.QueryAsync<T>(sql, parameters, commandType: CommandType.Text);
                    return rows;
                }
            }
            catch (Exception)
            {
                throw;
            }
        }


        public async Task SaveData<T>(string storedProcedure, T parameters, string connectionStringName)
        {
            try
            {
                string connectionString = GetConnectionString(connectionStringName);
                using (IDbConnection connection = new SqlConnection(connectionString))
                {
                    await connection.ExecuteAsync(storedProcedure, parameters, commandType: CommandType.StoredProcedure);
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        public async Task SaveDataRaw<T>(string sql, T parameters, string connectionStringName)
        {
            try
            {
                string connectionString = GetConnectionString(connectionStringName);
                using (IDbConnection connection = new SqlConnection(connectionString))
                {
                    await connection.ExecuteAsync(sql, parameters, commandType: CommandType.Text);
                }
            }
            catch (Exception)
            {
                throw;
            }
        }

        //Open Connection / Start Transaction Method
        private IDbConnection _connection;
        private IDbTransaction _transaction;

        public void StartTranscation(string connectionStringName)
        {
            string connectionString = GetConnectionString(connectionStringName);
            _connection = new SqlConnection(connectionString);
            _connection.Open();
            _transaction = _connection.BeginTransaction();
            IsClosed = false;
        }
        //load using thew transcation
        public List<T> LoadDataInTransaction<T, u>(string storedProcedure, u parameters)
        {
            List<T> rows = _connection.Query<T>(storedProcedure, parameters,
                commandType: CommandType.StoredProcedure, transaction: _transaction).ToList();
            return rows;
        }
        //Save using the transcation
        public void SaveDataInTranscation<T>(string storedProcedure, T parameters)
        {

            _connection.Execute(storedProcedure, parameters,
                commandType: CommandType.StoredProcedure, transaction: _transaction);
        }
        //Close Connection/ Stop Transaction Method

        private bool IsClosed = false;
        private readonly IConfiguration config;
        private readonly ILogger<SqlDataAccess> logger;

        public void CommitTransaction()
        {
            _transaction?.Commit();
            _connection?.Close();
            IsClosed = true;
        }
        public void RollbackTransaction()
        {
            _transaction?.Rollback();
            _connection?.Close();
            IsClosed = true;
        }
        //dispose
        public void Dispose()
        {
            if (IsClosed == false)
            {
                try
                {
                    CommitTransaction();
                }
                catch
                {

                    //TODO - Log this issue
                }
            }
            _transaction = null;
            _connection = null;
        }

        public class DataAccessException : Exception
        {
            public DataAccessException(string message, Exception innerException)
                : base(message, innerException)
            {
            }
        }

    }
}
